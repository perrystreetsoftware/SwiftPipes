import Foundation

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
    var isConnected: Bool = false
    
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
