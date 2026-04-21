import Foundation
import Combine
import AppKit
import UserNotifications

class SSHTunnelManager: ObservableObject {
    @Published var tunnels: [SSHTunnel] = []
    @Published var hasActiveConnections = false
    
    private var processes: [UUID: Process] = [:]
    private let proxyManager = NetworkProxyManager()
    
    init() {
        loadTunnels()
        setupCleanupOnTermination()
        requestNotificationPermissions()
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
        
        // Define notification categories
        let connectAction = UNNotificationAction(identifier: "CONNECT_ACTION",
                                                   title: "Open SwiftPipes",
                                                   options: .foreground)
        
        let category = UNNotificationCategory(identifier: "CONNECTION_STATUS",
                                               actions: [connectAction],
                                               intentIdentifiers: [],
                                               options: [])
        
        center.setNotificationCategories([category])
        
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
        content.categoryIdentifier = "CONNECTION_STATUS"
        
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
        
        // Check if port is already in use
        if isPortInUse(port: tunnel.localPort) {
            print("Port \(tunnel.localPort) is already in use. Cannot connect.")
            tunnels[index].connectionState = .failed("Local port \(tunnel.localPort) is already in use")
            updateActiveConnectionStatus()
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
                    tunnels[index].connectionState = .failed("Failed to start ssh: \(error.localizedDescription)")
                    updateActiveConnectionStatus()
                    return
                }
            } else {
                do {
                    try process.run()
                } catch {
                    print("Failed to start SSH process: \(error)")
                    tunnels[index].connectionState = .failed("Failed to start ssh: \(error.localizedDescription)")
                    updateActiveConnectionStatus()
                    return
                }
            }
        } else {
            do {
                try process.run()
            } catch {
                print("Failed to start SSH process: \(error)")
                tunnels[index].connectionState = .failed("Failed to start ssh: \(error.localizedDescription)")
                updateActiveConnectionStatus()
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
        let autoConfigureProxy = tunnel.autoConfigureProxy
        let bindHost = tunnel.localBindAddress
        let bindPort = tunnel.localPort

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
                    self.tunnels[idx].connectionState = .connected
                    self.updateActiveConnectionStatus()
                    if autoConfigureProxy {
                        self.proxyManager.enableSOCKSProxy(host: bindHost, port: bindPort)
                    }
                    self.showNotification(title: "Connected", body: "Connected to \(self.tunnels[idx].name)")
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
                    // Normal disconnect (process exited after being fully up)
                    self.tunnels[idx].connectionState = .disconnected
                    if autoConfigureProxy {
                        self.proxyManager.disableSOCKSProxy()
                    }
                    self.showNotification(
                        title: "Disconnected",
                        body: "Disconnected from \(self.tunnels[idx].name)"
                    )
                } else if case .connecting = self.tunnels[idx].connectionState {
                    // Process exited before we ever saw a successful handshake — this is
                    // the firewall/blocked case (or auth failure, DNS failure, etc.).
                    let reason = Self.summarizeSSHFailure(stderr: stderrText)
                    self.tunnels[idx].connectionState = .failed(reason)
                    self.showNotification(
                        title: "Connection Failed",
                        body: "\(self.tunnels[idx].name): \(reason)"
                    )
                }
                self.updateActiveConnectionStatus()
                self.processes.removeValue(forKey: tunnelId)
            }
        }
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
        if tunnel.autoConfigureProxy && wasConnected {
            proxyManager.disableSOCKSProxy()
        }

        if wasConnected {
            showNotification(title: "Disconnected", body: "Disconnected from \(tunnel.name)")
        }
    }
    
    private func updateActiveConnectionStatus() {
        hasActiveConnections = tunnels.contains { $0.isConnected }
    }
    
    private func saveTunnels() {
        if let data = try? JSONEncoder().encode(tunnels) {
            UserDefaults.standard.set(data, forKey: "savedTunnels")
        }
    }
    
    private func loadTunnels() {
        if let data = UserDefaults.standard.data(forKey: "savedTunnels"),
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
