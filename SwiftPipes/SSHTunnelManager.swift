import Foundation
import Combine
import AppKit
import UserNotifications

class SSHTunnelManager: ObservableObject {
    @Published var tunnels: [SSHTunnel] = []
    @Published var hasActiveConnections = false
    /// Non-nil when the last connect attempt failed because the server's host
    /// key doesn't match known_hosts. The view layer presents an alert with
    /// Accept / Cancel options.
    @Published var pendingHostKeyPrompt: HostKeyPrompt?

    private var processes: [UUID: Process] = [:]
    private let proxyManager = NetworkProxyManager()
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        loadTunnels()
        setupCleanupOnTermination()
        requestNotificationPermissions()
        sweepOrphanedSystemProxy()
        sweepOrphanedSwiftPipesSshProcesses()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupCleanupOnTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
    }
    
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Failed to request notification permissions: \(error)")
            }
        }
    }
    
    private func showNotification(title: String, body: String) {
        guard PreferencesManager.shared.showNotifications else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            }
        }
    }
    
    private func cleanup() {
        // Disconnect all active connections
        for tunnel in tunnels where tunnel.isConnected || tunnel.isConnecting {
            disconnect(tunnel.id)
        }
        
        // Kill any remaining SSH processes
        for (_, process) in processes {
            if process.isRunning {
                process.terminate()
            }
        }
        processes.removeAll()
    }
    
    var hasActiveConnection: Bool {
        tunnels.contains { $0.isConnected }
    }
    
    func addTunnel(_ tunnel: SSHTunnel) {
        tunnels.append(tunnel)
        saveTunnels()
    }
    
    func updateTunnel(_ tunnel: SSHTunnel) {
        if let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            let wasConnected = tunnels[index].isConnected || tunnels[index].isConnecting
            tunnels[index] = tunnel
            if wasConnected {
                disconnect(tunnel.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.connect(tunnel.id)
                }
            }
            saveTunnels()
        }
    }
    
    func deleteTunnel(_ tunnel: SSHTunnel) {
        if tunnel.isConnected || tunnel.isConnecting {
            disconnect(tunnel.id)
        }
        // Delete password from keychain
        _ = KeychainHelper.shared.delete(forKey: tunnel.passwordKeychainKey)
        tunnels.removeAll { $0.id == tunnel.id }
        saveTunnels()
    }

    /// Duplicates a tunnel, producing an independent copy with a fresh id, a
    /// disambiguated name, and — if the source had a stored password — a copy
    /// of that password keyed to the new tunnel's keychain entry. The duplicate
    /// is inserted immediately after the source in the list and is returned.
    @discardableResult
    func duplicateTunnel(_ tunnel: SSHTunnel) -> SSHTunnel {
        var copy = tunnel
        copy.id = UUID()
        copy.name = uniqueDuplicateName(basedOn: tunnel.name)
        copy.connectionState = .disconnected

        // Copy password in the keychain, if present. Best-effort: failure to
        // copy just means the user re-enters it in the editor.
        if let password = KeychainHelper.shared.get(forKey: tunnel.passwordKeychainKey),
           !password.isEmpty {
            _ = KeychainHelper.shared.save(password, forKey: copy.passwordKeychainKey)
        }

        if let sourceIdx = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            tunnels.insert(copy, at: sourceIdx + 1)
        } else {
            tunnels.append(copy)
        }
        saveTunnels()
        return copy
    }

    /// Picks a name like "Foo Copy", "Foo Copy 2", ... that doesn't collide
    /// with any existing tunnel name.
    private func uniqueDuplicateName(basedOn name: String) -> String {
        let base = name.isEmpty ? "Connection" : name
        let existing = Set(tunnels.map { $0.name })
        let firstCandidate = "\(base) Copy"
        if !existing.contains(firstCandidate) { return firstCandidate }
        var n = 2
        while existing.contains("\(base) Copy \(n)") { n += 1 }
        return "\(base) Copy \(n)"
    }
    
    func toggleConnection(_ tunnelId: UUID) {
        if let index = tunnels.firstIndex(where: { $0.id == tunnelId }) {
            if tunnels[index].isConnected || tunnels[index].isConnecting {
                disconnect(tunnelId)
            } else {
                connect(tunnelId)
            }
        }
    }
    
    func connect(_ tunnelId: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let tunnel = tunnels[index]

        // Single-connection policy: if any other tunnel is active, disconnect it first,
        // then re-enter connect() after a short delay so the old process has time to
        // release its local port and proxy config is fully torn down.
        let others = tunnels.filter { $0.id != tunnelId && $0.isConnected }
        if !others.isEmpty {
            for other in others {
                disconnect(other.id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.connect(tunnelId)
            }
            return
        }

        // Check if port is already in use
        if isPortInUse(port: tunnel.localPort) {
            print("Port \(tunnel.localPort) is already in use. Cannot connect.")
            let holder = describePortHolder(port: tunnel.localPort)
            let reason = portInUseReasonFor(port: tunnel.localPort, holder: holder)
            tunnels[index].connectionState = .failed(reason)
            updateActiveConnectionStatus()
            showNotification(
                title: "Connection Failed",
                body: "\(tunnel.name): \(reason)"
            )
            clearOrphanedProxyIfAny()
            // If the holder is a leftover SwiftPipes tunnel, offer to recover.
            if let holder = holder {
                switch holder {
                case .ours, .orphanedSwiftPipes:
                    presentPortInUseRecoveryAlert(
                        tunnelId: tunnelId,
                        port: tunnel.localPort,
                        holder: holder
                    )
                case .foreign:
                    break
                }
            }
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var arguments = [
            "-v", // verbose so we can detect real authentication success on stderr
            "-D", "\(tunnel.localBindAddress):\(tunnel.localPort)",
            "-N",
            "-p", "\(tunnel.port)",
            "-o", "ConnectTimeout=10",
            "-o", "ExitOnForwardFailure=yes"
        ]
        
        if !tunnel.strictHostKeyChecking {
            arguments += ["-o", "StrictHostKeyChecking=no"]
            arguments += ["-o", "UserKnownHostsFile=/dev/null"]
        } else {
            // Even with strict checking, add accept-new to avoid the initial prompt
            arguments += ["-o", "StrictHostKeyChecking=accept-new"]
        }
        
        if tunnel.useIdentityFile && !tunnel.identityFilePath.isEmpty {
            let expandedPath = NSString(string: tunnel.identityFilePath).expandingTildeInPath
            arguments += ["-i", expandedPath]
        }
        
        // Add ServerAliveInterval to keep connection alive
        if tunnel.serverAliveInterval > 0 {
            arguments += ["-o", "ServerAliveInterval=\(tunnel.serverAliveInterval)"]
            arguments += ["-o", "ServerAliveCountMax=3"]
        }
        
        arguments.append("\(tunnel.username)@\(tunnel.sshServer)")
        
        process.arguments = arguments

        // Capture stderr so we can observe real connection progress. SSH's -v output
        // prints "Authenticated to <host>" once auth succeeds and "Local forwarding
        // listening on ..." once the SOCKS listener is bound. Only after both do we
        // consider the tunnel actually usable.
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        if !tunnel.useIdentityFile {
            // Get password from keychain
            if let password = KeychainHelper.shared.get(forKey: tunnel.passwordKeychainKey), !password.isEmpty {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                
                do {
                    try process.run()
                    if let data = (password + "\n").data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                        try? stdinPipe.fileHandleForWriting.close()
                    }
                } catch {
                    print("Failed to start SSH process: \(error)")
                    let reason = "Failed to start ssh: \(error.localizedDescription)"
                    tunnels[index].connectionState = .failed(reason)
                    updateActiveConnectionStatus()
                    showNotification(
                        title: "Connection Failed",
                        body: "\(tunnel.name): \(reason)"
                    )
                    clearOrphanedProxyIfAny()
                    return
                }
            } else {
                do {
                    try process.run()
                } catch {
                    print("Failed to start SSH process: \(error)")
                    let reason = "Failed to start ssh: \(error.localizedDescription)"
                    tunnels[index].connectionState = .failed(reason)
                    updateActiveConnectionStatus()
                    showNotification(
                        title: "Connection Failed",
                        body: "\(tunnel.name): \(reason)"
                    )
                    clearOrphanedProxyIfAny()
                    return
                }
            }
        } else {
            do {
                try process.run()
            } catch {
                print("Failed to start SSH process: \(error)")
                let reason = "Failed to start ssh: \(error.localizedDescription)"
                tunnels[index].connectionState = .failed(reason)
                updateActiveConnectionStatus()
                showNotification(
                    title: "Connection Failed",
                    body: "\(tunnel.name): \(reason)"
                )
                clearOrphanedProxyIfAny()
                return
            }
        }
        
        processes[tunnelId] = process
        tunnels[index].connectionState = .connecting
        updateActiveConnectionStatus()

        // Monitor ssh verbose stderr output to detect real connection success/failure.
        // We only enable the system SOCKS proxy and show the green indicator once we
        // see evidence that authentication completed and the forward listener is up.
        // This prevents the "green light but nothing loads" bug when an outbound
        // firewall silently drops the SSH handshake.
        var stderrBuffer = Data()
        var sawAuthenticated = false
        var sawForwardListening = false
        var markedConnected = false
        let stderrHandle = stderrPipe.fileHandleForReading
        let proxyMode = tunnel.proxyMode
        let selectiveHosts = tunnel.selectiveHosts
        let bindHost = tunnel.localBindAddress
        let bindPort = tunnel.localPort
        let tunnelName = tunnel.name

        stderrHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            stderrBuffer.append(chunk)
            guard let text = String(data: stderrBuffer, encoding: .utf8) else { return }

            if !sawAuthenticated && text.contains("Authenticated to ") {
                sawAuthenticated = true
            }
            if !sawForwardListening &&
                (text.contains("Local forwarding listening on") ||
                 text.contains("dynamic forward")) {
                sawForwardListening = true
            }

            if sawAuthenticated && sawForwardListening && !markedConnected {
                markedConnected = true
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard let idx = self.tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
                    // Only transition if we're still in the connecting state for this attempt
                    guard case .connecting = self.tunnels[idx].connectionState else { return }

                    switch proxyMode {
                    case .off:
                        break
                    case .all:
                        self.proxyManager.enableSOCKSProxy(host: bindHost, port: bindPort)
                    case .selective:
                        let rules = selectiveHosts.compactMap { ProxyRule.parse($0) }
                        let ok = self.proxyManager.enableSelectiveSOCKS(
                            host: bindHost,
                            port: bindPort,
                            rules: rules
                        )
                        if !ok {
                            self.showNotification(
                                title: "Connection Failed",
                                body: "Could not start local PAC server for \(tunnelName). Disconnecting."
                            )
                            self.disconnect(tunnelId)
                            return
                        }
                    }

                    self.tunnels[idx].connectionState = .connected
                    self.updateActiveConnectionStatus()
                }
            }
        }

        DispatchQueue.global().async {
            process.waitUntilExit()
            // Drain any remaining stderr and stop the readability handler.
            let remaining = stderrHandle.readDataToEndOfFile()
            if !remaining.isEmpty {
                stderrBuffer.append(remaining)
            }
            stderrHandle.readabilityHandler = nil
            let stderrText = String(data: stderrBuffer, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                guard let idx = self.tunnels.firstIndex(where: { $0.id == tunnelId }) else {
                    self.processes.removeValue(forKey: tunnelId)
                    return
                }

                let wasConnected = self.tunnels[idx].isConnected
                if wasConnected {
                    // Unsolicited drop: ssh died while we still believed we were
                    // connected. User-initiated disconnects set .disconnected
                    // *before* terminating the process, so this branch only
                    // fires for real drops (network change, server reboot,
                    // sleep/wake, idle timeout). The user's proxied apps just
                    // stopped working — they need to know.
                    let tunnelName = self.tunnels[idx].name
                    self.tunnels[idx].connectionState = .disconnected
                    if proxyMode != .off {
                        // Clear both classic SOCKS and PAC autoproxy state defensively.
                        self.proxyManager.disableAllProxyConfig()
                    }
                    self.showNotification(
                        title: "Tunnel Dropped",
                        body: "\(tunnelName) disconnected unexpectedly"
                    )
                } else if case .connecting = self.tunnels[idx].connectionState {
                    // Process exited before we ever saw a successful handshake — this is
                    // the firewall/blocked case (or auth failure, DNS failure, etc.).
                    let tunnel = self.tunnels[idx]
                    if stderrText.contains("Host key verification failed") ||
                       stderrText.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
                        // Surface a prompt so the user can accept the new key and reconnect.
                        self.tunnels[idx].connectionState = .failed("Host key verification failed")
                        self.showNotification(
                            title: "Connection Failed",
                            body: "\(tunnel.name): host key changed — action required"
                        )
                        if let prompt = Self.parseHostKeyChange(
                            stderr: stderrText,
                            tunnelId: tunnelId,
                            host: tunnel.sshServer,
                            port: tunnel.port
                        ) {
                            self.pendingHostKeyPrompt = prompt
                            self.presentHostKeyAlert(prompt)
                        }
                    } else {
                        let reason = Self.summarizeSSHFailure(stderr: stderrText)
                        self.tunnels[idx].connectionState = .failed(reason)
                        self.showNotification(
                            title: "Connection Failed",
                            body: "\(tunnel.name): \(reason)"
                        )
                    }
                    self.clearOrphanedProxyIfAny()
                }
                self.updateActiveConnectionStatus()
                self.processes.removeValue(forKey: tunnelId)
            }
        }
    }

    /// Classified description of whatever process is holding a local port.
    enum PortHolder {
        /// A live ssh process spawned by THIS app instance (in `processes`).
        case ours(pid: Int)
        /// An orphaned ssh whose argv matches the SwiftPipes invocation
        /// signature — i.e. a leftover from a crashed / force-quit session.
        case orphanedSwiftPipes(pid: Int, command: String)
        /// Anything else: another app, the user's own ssh, etc. We never kill these.
        case foreign(command: String, pid: Int)

        var pid: Int {
            switch self {
            case .ours(let p), .orphanedSwiftPipes(let p, _), .foreign(_, let p): return p
            }
        }
    }

    /// Build a human-readable reason for a "local port already in use" failure.
    /// Caller passes a pre-computed holder to avoid running lsof/ps twice.
    private func portInUseReasonFor(port: Int, holder: PortHolder?) -> String {
        guard let holder = holder else {
            return "Local port \(port) is already in use"
        }
        switch holder {
        case .ours:
            return "Local port \(port) is already in use by another SwiftPipes tunnel — disconnect it first"
        case .orphanedSwiftPipes(let pid, _):
            return "Local port \(port) is held by a leftover SwiftPipes tunnel from a previous session (PID \(pid))"
        case .foreign(let command, let pid):
            return "Local port \(port) is already in use by \(command) (PID \(pid))"
        }
    }

    /// Inspect what is listening on a TCP port and classify it. Combines lsof
    /// (for PID + command name) with `ps` (for full argv) so we can recognize
    /// our own leftover ssh processes by their flag signature.
    func describePortHolder(port: Int) -> PortHolder? {
        guard let (command, pid) = Self.lsofListener(port: port) else { return nil }
        let ourPids = Set(processes.values.compactMap { $0.isRunning ? Int($0.processIdentifier) : nil })
        if ourPids.contains(pid) {
            return .ours(pid: pid)
        }
        if command.hasPrefix("ssh"), let argv = Self.psCommandLine(pid: pid),
           Self.isSwiftPipesSshArgv(argv) {
            return .orphanedSwiftPipes(pid: pid, command: argv)
        }
        return .foreign(command: command, pid: pid)
    }

    /// First listening process on the given TCP port (own user only), via lsof.
    /// Returns nil if lsof is missing, errors, or finds nothing.
    static func lsofListener(port: Int) -> (command: String, pid: Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            let command = String(fields[0])
            guard let pid = Int(fields[1]) else { continue }
            return (command, pid)
        }
        return nil
    }

    /// Full command line of a process via `ps -ww -p <pid> -o command=`.
    /// Returns nil on error or if the pid isn't running.
    static func psCommandLine(pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", "\(pid)", "-o", "command="]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Heuristic: does this command line look like a SwiftPipes-spawned ssh
    /// tunnel? We look for the exact set of flags `connect()` always passes.
    /// Multiple matches together make false-positives effectively impossible.
    static func isSwiftPipesSshArgv(_ command: String) -> Bool {
        guard command.hasPrefix("/usr/bin/ssh ") || command.hasPrefix("/usr/bin/ssh\t") else {
            return false
        }
        // SwiftPipes always passes:  -v   -D <addr>:<port>   -N
        //                            -o ConnectTimeout=10
        //                            -o ExitOnForwardFailure=yes
        let required = [
            " -D ",
            " -N ",
            "ConnectTimeout=10",
            "ExitOnForwardFailure=yes",
        ]
        for needle in required where !command.contains(needle) {
            return false
        }
        return true
    }

    /// Extract a short human-readable reason from ssh -v stderr output.
    static func summarizeSSHFailure(stderr: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        // Look for common, user-meaningful error signatures first.
        let signatures: [(String, String)] = [
            ("Connection timed out", "Connection timed out (host unreachable or blocked by firewall)"),
            ("Operation timed out", "Connection timed out (host unreachable or blocked by firewall)"),
            ("No route to host", "No route to host (possibly blocked by firewall)"),
            ("Connection refused", "Connection refused by server"),
            ("Permission denied", "Authentication failed"),
            ("Host key verification failed", "Host key verification failed"),
            ("Could not resolve hostname", "Could not resolve hostname"),
            ("port forwarding failed", "Port forwarding failed")
        ]
        for (needle, message) in signatures where stderr.contains(needle) {
            return message
        }
        // Fall back to the last non-debug line, if any.
        if let last = lines.reversed().first(where: { !$0.hasPrefix("debug") && !$0.isEmpty }) {
            return last
        }
        return "SSH process exited before the tunnel was established"
    }

    /// Called once at launch. If any system proxy is still on, it must be an
    /// orphan from a previous crash / force-quit (all tunnels decode as
    /// .disconnected, so no live session could have put it there). Read checks
    /// don't need sudo; disable only runs if there's actually something to clean.
    private func sweepOrphanedSystemProxy() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if self.proxyManager.isAnyProxyActive() {
                print("SwiftPipes: found orphaned system proxy at launch — clearing")
                self.proxyManager.disableAllProxyConfig()
            }
        }
    }

    /// Called once at launch alongside the proxy sweep. Finds ssh processes
    /// that look like SwiftPipes-spawned tunnels with PPID==1 (reparented to
    /// launchd, i.e. their original SwiftPipes parent died) and SIGTERMs them.
    /// At launch every saved tunnel is `.disconnected`, so any matching ssh
    /// can only be a leftover.
    private func sweepOrphanedSwiftPipesSshProcesses() {
        DispatchQueue.global(qos: .utility).async {
            let orphans = Self.findOrphanedSwiftPipesSshPids()
            guard !orphans.isEmpty else { return }
            for pid in orphans {
                _ = kill(pid_t(pid), SIGTERM)
            }
            print("SwiftPipes: cleaned \(orphans.count) orphaned ssh tunnel(s) at launch: \(orphans)")
        }
    }

    /// Enumerate processes via `ps -axwwo pid=,ppid=,command=` and return PIDs
    /// for processes whose argv matches the SwiftPipes-ssh signature AND whose
    /// PPID is 1 (orphaned, reparented to launchd). Returning [] on any error
    /// is fine — the sweep is best-effort.
    static func findOrphanedSwiftPipesSshPids() -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axwwo", "pid=,ppid=,command="]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var orphans: [Int] = []
        for rawLine in output.split(separator: "\n") {
            // ps emits leading spaces for right-aligned numeric columns; trim them.
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Split into pid, ppid, command (max 3 substrings).
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 3,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { continue }
            guard ppid == 1 else { continue }
            let command = String(parts[2])
            if isSwiftPipesSshArgv(command) {
                orphans.append(pid)
            }
        }
        return orphans
    }

    /// Modal alert offering to terminate a leftover/duplicate SwiftPipes ssh
    /// process holding the local port and retry the connection. Mirrors
    /// `presentHostKeyAlert` in style.
    private func presentPortInUseRecoveryAlert(
        tunnelId: UUID,
        port: Int,
        holder: PortHolder
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Port \(port) is held by a previous SwiftPipes tunnel"

        let pid = holder.pid
        var info = ""
        switch holder {
        case .ours:
            info = "Another active SwiftPipes tunnel (PID \(pid)) is currently bound to port \(port).\n\nTerminate it and retry this connection?"
        case .orphanedSwiftPipes(_, let command):
            info = "A leftover ssh process (PID \(pid)) from a prior SwiftPipes session is still bound to port \(port). Terminate it and retry the connection?\n\n\(command)"
        case .foreign:
            // Should not reach here — caller filters foreign holders out.
            return
        }
        alert.informativeText = info

        alert.addButton(withTitle: "Recover and Reconnect")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // SIGTERM the holder, wait briefly for the kernel to release the port,
        // then retry. All of this happens off the main thread so the UI doesn't
        // freeze during the wait; we hop back for the actual reconnect.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = kill(pid_t(pid), SIGTERM)
            // Poll up to ~1.5s for the port to be released.
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline {
                if self?.isPortInUse(port: port) == false { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            DispatchQueue.main.async {
                self?.connect(tunnelId)
            }
        }
    }

    /// Defensive proxy clear on failure paths. Gated on the read-only probe so
    /// we don't prompt for sudo when the system is already clean.
    private func clearOrphanedProxyIfAny() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if self.proxyManager.isAnyProxyActive() {
                self.proxyManager.disableAllProxyConfig()
            }
        }
    }

    /// Called from the view layer when the user confirms the new host key.
    /// Removes the stale known_hosts entries and re-runs connect(), which
    /// re-learns the key via StrictHostKeyChecking=accept-new.
    func acceptNewHostKeyAndReconnect(promptId: UUID) {
        guard let prompt = pendingHostKeyPrompt, prompt.id == promptId else { return }
        let tunnelId = prompt.tunnelId
        let host = prompt.host
        let port = prompt.port

        pendingHostKeyPrompt = nil

        runSSHKeygenRemove(host: host, port: nil)
        if port != 22 {
            runSSHKeygenRemove(host: host, port: port)
        }

        connect(tunnelId)
    }

    /// Called from the view layer when the user cancels the host-key prompt.
    func rejectHostKey(promptId: UUID) {
        guard let prompt = pendingHostKeyPrompt, prompt.id == promptId else { return }
        if let idx = tunnels.firstIndex(where: { $0.id == prompt.tunnelId }) {
            tunnels[idx].connectionState = .failed("Host key rejected by user")
        }
        pendingHostKeyPrompt = nil
        updateActiveConnectionStatus()
    }

    private func runSSHKeygenRemove(host: String, port: Int?) {
        let target: String
        if let port = port {
            target = "[\(host)]:\(port)"
        } else {
            target = host
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-R", target]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to run ssh-keygen -R \(target): \(error)")
        }
    }

    /// Extract key-type, new fingerprint, and the offending known_hosts path
    /// from ssh -v stderr when a host-key-changed failure occurred.
    static func parseHostKeyChange(
        stderr: String,
        tunnelId: UUID,
        host: String,
        port: Int
    ) -> HostKeyPrompt? {
        guard stderr.contains("Host key verification failed") ||
              stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") else {
            return nil
        }

        let lines = stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)

        var keyType = "unknown"
        var newFingerprint = "unknown"
        // Prefer the "debug1: Server host key: <type> SHA256:<hash>" line, which
        // ssh -v prints before the failure banner.
        if let line = lines.first(where: {
            $0.contains("Server host key:") && $0.contains("SHA256:")
        }) {
            let tokens = line.split(separator: " ").map(String.init)
            for t in tokens where t.hasPrefix("SHA256:") {
                newFingerprint = t
                break
            }
            if let typeIdx = tokens.firstIndex(of: "key:"), typeIdx + 1 < tokens.count {
                keyType = normalizeKeyType(tokens[typeIdx + 1])
            }
        }

        // "Offending ED25519 key in /Users/foo/.ssh/known_hosts:42"
        var knownHostsPath: String? = nil
        if let line = lines.first(where: { $0.contains("Offending") && $0.contains("key in") }) {
            let tokens = line.split(separator: " ").map(String.init)
            if let offIdx = tokens.firstIndex(of: "Offending"), offIdx + 1 < tokens.count {
                keyType = normalizeKeyType(tokens[offIdx + 1])
            }
            if let inRange = line.range(of: "key in ") {
                let pathAndLine = String(line[inRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if let colon = pathAndLine.lastIndex(of: ":") {
                    knownHostsPath = String(pathAndLine[..<colon])
                } else {
                    knownHostsPath = pathAndLine
                }
            }
        }

        return HostKeyPrompt(
            tunnelId: tunnelId,
            host: host,
            port: port,
            keyType: keyType,
            newFingerprint: newFingerprint,
            previousFingerprint: nil,
            knownHostsPath: knownHostsPath
        )
    }

    /// Present an NSAlert describing the host-key change and route the user's
    /// choice back into accept / reject. Runs on the main thread.
    private func presentHostKeyAlert(_ prompt: HostKeyPrompt) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Host key changed for \(prompt.host)"

        var info = "The SSH server's key doesn't match what's recorded in known_hosts.\n\n"
        info += "This can happen legitimately if the server was rebuilt — or it can indicate someone is impersonating the server (man-in-the-middle attack). Only accept the new key if you were expecting the change.\n\n"
        info += "Key type: \(prompt.keyType)\n"
        info += "New fingerprint:\n\(prompt.newFingerprint)"
        if let prev = prompt.previousFingerprint {
            info += "\n\nPrevious fingerprint:\n\(prev)"
        }
        if let path = prompt.knownHostsPath {
            info += "\n\nFile: \(path)"
        }
        alert.informativeText = info

        alert.addButton(withTitle: "Accept and Reconnect")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            acceptNewHostKeyAndReconnect(promptId: prompt.id)
        } else {
            rejectHostKey(promptId: prompt.id)
        }
    }

    private static func normalizeKeyType(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower == "ssh-ed25519" || lower == "ed25519" { return "ED25519" }
        if lower == "ssh-rsa" || lower == "rsa" { return "RSA" }
        if lower == "ssh-dss" || lower == "dsa" { return "DSA" }
        if lower.hasPrefix("ecdsa") { return "ECDSA" }
        return raw
    }

    func disconnect(_ tunnelId: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let tunnel = tunnels[index]
        let wasConnected = tunnel.isConnected

        if let process = processes[tunnelId], process.isRunning {
            process.terminate()
            processes.removeValue(forKey: tunnelId)
        }

        tunnels[index].connectionState = .disconnected
        updateActiveConnectionStatus()

        // Only touch the system proxy if we actually had it enabled (i.e. we were
        // fully connected). Disabling on a failed/in-progress attempt is harmless
        // but we still skip the "Disconnected" notification for clarity.
        if wasConnected && tunnel.proxyMode != .off {
            // Defensively clear both classic SOCKS and PAC autoproxy state so a mode
            // change between sessions can't leave stale system-wide config behind.
            proxyManager.disableAllProxyConfig()
        }

    }

    private func updateActiveConnectionStatus() {
        hasActiveConnections = tunnels.contains { $0.isConnected }
    }
    
    private func saveTunnels() {
        if let data = try? JSONEncoder().encode(tunnels) {
            defaults.set(data, forKey: "savedTunnels")
        }
    }

    private func loadTunnels() {
        if let data = defaults.data(forKey: "savedTunnels"),
           let decoded = try? JSONDecoder().decode([SSHTunnel].self, from: data) {
            // connectionState is intentionally not persisted — always start disconnected.
            tunnels = decoded
        }
    }
    
    private func isPortInUse(port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD != -1 else { return false }
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        close(socketFD)
        return bindResult == -1
    }
}
