import Foundation

enum ConnectionState: Equatable, Hashable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

enum ProxyMode: String, Codable, CaseIterable, Hashable {
    case off
    case all
    case selective
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
    var proxyMode: ProxyMode
    var selectiveHosts: [String]
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

    init(
        name: String = "",
        sshServer: String = "",
        port: Int = 22,
        username: String = "",
        localBindAddress: String = "localhost",
        localPort: Int = 8158,
        autoConfigureProxy: Bool = true,
        proxyMode: ProxyMode = .all,
        selectiveHosts: [String] = [],
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
        self.proxyMode = proxyMode
        self.selectiveHosts = selectiveHosts
        self.useIdentityFile = useIdentityFile
        self.identityFilePath = identityFilePath
        self.strictHostKeyChecking = strictHostKeyChecking
        self.serverAliveInterval = serverAliveInterval
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sshServer, port, username, localBindAddress, localPort
        case autoConfigureProxy, proxyMode, selectiveHosts
        case useIdentityFile, identityFilePath, strictHostKeyChecking
        case serverAliveInterval
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sshServer = try c.decodeIfPresent(String.self, forKey: .sshServer) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        localBindAddress = try c.decodeIfPresent(String.self, forKey: .localBindAddress) ?? "localhost"
        localPort = try c.decodeIfPresent(Int.self, forKey: .localPort) ?? 8158
        autoConfigureProxy = try c.decodeIfPresent(Bool.self, forKey: .autoConfigureProxy) ?? true
        selectiveHosts = try c.decodeIfPresent([String].self, forKey: .selectiveHosts) ?? []
        useIdentityFile = try c.decodeIfPresent(Bool.self, forKey: .useIdentityFile) ?? false
        identityFilePath = try c.decodeIfPresent(String.self, forKey: .identityFilePath) ?? ""
        strictHostKeyChecking = try c.decodeIfPresent(Bool.self, forKey: .strictHostKeyChecking) ?? true
        serverAliveInterval = try c.decodeIfPresent(Int.self, forKey: .serverAliveInterval) ?? 30

        if let mode = try c.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) {
            proxyMode = mode
        } else {
            // Migrate: pre-selective-proxy saves only had autoConfigureProxy.
            proxyMode = autoConfigureProxy ? .all : .off
        }
    }
}
