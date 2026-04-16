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
        for tunnel in tunnels where tunnel.isConnected {
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
            let wasConnected = tunnels[index].isConnected
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
        if tunnel.isConnected {
            disconnect(tunnel.id)
        }
        // Delete password from keychain
        _ = KeychainHelper.shared.delete(forKey: tunnel.passwordKeychainKey)
        tunnels.removeAll { $0.id == tunnel.id }
        saveTunnels()
    }
    
    func toggleConnection(_ tunnelId: UUID) {
        if let index = tunnels.firstIndex(where: { $0.id == tunnelId }) {
            if tunnels[index].isConnected {
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
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var arguments = [
            "-D", "\(tunnel.localBindAddress):\(tunnel.localPort)",
            "-N",
            "-p", "\(tunnel.port)"
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
        
        if !tunnel.useIdentityFile {
            // Get password from keychain
            if let password = KeychainHelper.shared.get(forKey: tunnel.passwordKeychainKey), !password.isEmpty {
                let pipe = Pipe()
                process.standardInput = pipe
                
                do {
                    try process.run()
                    if let data = (password + "\n").data(using: .utf8) {
                        pipe.fileHandleForWriting.write(data)
                        try? pipe.fileHandleForWriting.close()
                    }
                } catch {
                    print("Failed to start SSH process: \(error)")
                    return
                }
            } else {
                do {
                    try process.run()
                } catch {
                    print("Failed to start SSH process: \(error)")
                    return
                }
            }
        } else {
            do {
                try process.run()
            } catch {
                print("Failed to start SSH process: \(error)")
                return
            }
        }
        
        processes[tunnelId] = process
        tunnels[index].isConnected = true
        updateActiveConnectionStatus()
        
        if tunnel.autoConfigureProxy {
            proxyManager.enableSOCKSProxy(host: tunnel.localBindAddress, port: tunnel.localPort)
        }
        
        showNotification(title: "Connected", body: "Connected to \(tunnel.name)")
        
        DispatchQueue.global().async {
            process.waitUntilExit()
            DispatchQueue.main.async {
                if let idx = self.tunnels.firstIndex(where: { $0.id == tunnelId }) {
                    self.tunnels[idx].isConnected = false
                    self.updateActiveConnectionStatus()
                }
                self.processes.removeValue(forKey: tunnelId)
            }
        }
    }
    
    func disconnect(_ tunnelId: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let tunnel = tunnels[index]
        
        if let process = processes[tunnelId], process.isRunning {
            process.terminate()
            processes.removeValue(forKey: tunnelId)
        }
        
        tunnels[index].isConnected = false
        updateActiveConnectionStatus()
        
        if tunnel.autoConfigureProxy {
            proxyManager.disableSOCKSProxy()
        }
        
        showNotification(title: "Disconnected", body: "Disconnected from \(tunnel.name)")
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
            tunnels = decoded.map { tunnel in
                var t = tunnel
                t.isConnected = false
                return t
            }
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
