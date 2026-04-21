import Foundation

enum ConnectionState: Equatable, Hashable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct SSHTunnel: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var sshServer: String
    var port: Int
    var username: String
    var localBindAddress: String
    var localPort: Int
    var autoConfigureProxy: Bool
    var useIdentityFile: Bool
    var identityFilePath: String
    var strictHostKeyChecking: Bool
    var serverAliveInterval: Int
    var connectionState: ConnectionState = .disconnected

    /// True only when the SSH tunnel has authenticated and is actively forwarding.
    /// A connection that is still being established (pre-auth) is NOT considered connected;
    /// this prevents showing a green status when the firewall is silently dropping traffic.
    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = connectionState { return true }
        return false
    }

    // Password is not stored in the struct - use Keychain instead
    var passwordKeychainKey: String {
        return "ssh-password-\(id.uuidString)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sshServer, port, username, localBindAddress, localPort,
             autoConfigureProxy, useIdentityFile, identityFilePath,
             strictHostKeyChecking, serverAliveInterval
    }
    
    init(
        name: String = "",
        sshServer: String = "",
        port: Int = 22,
        username: String = "",
        localBindAddress: String = "localhost",
        localPort: Int = 8158,
        autoConfigureProxy: Bool = true,
        useIdentityFile: Bool = false,
        identityFilePath: String = "",
        strictHostKeyChecking: Bool = true,
        serverAliveInterval: Int = 30
    ) {
        self.name = name
        self.sshServer = sshServer
        self.port = port
        self.username = username
        self.localBindAddress = localBindAddress
        self.localPort = localPort
        self.autoConfigureProxy = autoConfigureProxy
        self.useIdentityFile = useIdentityFile
        self.identityFilePath = identityFilePath
        self.strictHostKeyChecking = strictHostKeyChecking
        self.serverAliveInterval = serverAliveInterval
    }
}
