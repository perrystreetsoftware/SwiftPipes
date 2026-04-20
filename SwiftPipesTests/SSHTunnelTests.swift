import XCTest
@testable import SwiftPipes

final class SSHTunnelTests: XCTestCase {
    
    func testTunnelInitialization() {
        let tunnel = SSHTunnel(
            name: "Test Connection",
            sshServer: "example.com",
            port: 22,
            username: "testuser",
            localBindAddress: "localhost",
            localPort: 8158,
            autoConfigureProxy: true,
            useIdentityFile: false,
            identityFilePath: "",
            strictHostKeyChecking: true
        )

        XCTAssertEqual(tunnel.name, "Test Connection")
        XCTAssertEqual(tunnel.sshServer, "example.com")
        XCTAssertEqual(tunnel.port, 22)
        XCTAssertEqual(tunnel.username, "testuser")
        XCTAssertEqual(tunnel.localBindAddress, "localhost")
        XCTAssertEqual(tunnel.localPort, 8158)
        XCTAssertTrue(tunnel.autoConfigureProxy)
        XCTAssertFalse(tunnel.useIdentityFile)
        XCTAssertTrue(tunnel.strictHostKeyChecking)
        XCTAssertFalse(tunnel.isConnected)
    }

    func testTunnelDefaultValues() {
        let tunnel = SSHTunnel()

        XCTAssertEqual(tunnel.name, "")
        XCTAssertEqual(tunnel.sshServer, "")
        XCTAssertEqual(tunnel.port, 22)
        XCTAssertEqual(tunnel.username, "")
        XCTAssertEqual(tunnel.localBindAddress, "localhost")
        XCTAssertEqual(tunnel.localPort, 8158)
        XCTAssertTrue(tunnel.autoConfigureProxy)
        XCTAssertEqual(tunnel.proxyMode, .all)
        XCTAssertTrue(tunnel.selectiveHosts.isEmpty)
        XCTAssertFalse(tunnel.useIdentityFile)
        XCTAssertEqual(tunnel.identityFilePath, "")
        XCTAssertTrue(tunnel.strictHostKeyChecking)
        XCTAssertFalse(tunnel.isConnected)
    }

    func testTunnelCodable() throws {
        let originalTunnel = SSHTunnel(
            name: "Test Connection",
            sshServer: "example.com",
            port: 2222,
            username: "testuser",
            localBindAddress: "127.0.0.1",
            localPort: 9999,
            autoConfigureProxy: false,
            proxyMode: .selective,
            selectiveHosts: ["www.example.com", "10.0.0.0/24"],
            useIdentityFile: true,
            identityFilePath: "/path/to/key",
            strictHostKeyChecking: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalTunnel)

        let decoder = JSONDecoder()
        let decodedTunnel = try decoder.decode(SSHTunnel.self, from: data)

        XCTAssertEqual(decodedTunnel.name, originalTunnel.name)
        XCTAssertEqual(decodedTunnel.sshServer, originalTunnel.sshServer)
        XCTAssertEqual(decodedTunnel.port, originalTunnel.port)
        XCTAssertEqual(decodedTunnel.username, originalTunnel.username)
        XCTAssertEqual(decodedTunnel.localBindAddress, originalTunnel.localBindAddress)
        XCTAssertEqual(decodedTunnel.localPort, originalTunnel.localPort)
        XCTAssertEqual(decodedTunnel.autoConfigureProxy, originalTunnel.autoConfigureProxy)
        XCTAssertEqual(decodedTunnel.proxyMode, .selective)
        XCTAssertEqual(decodedTunnel.selectiveHosts, originalTunnel.selectiveHosts)
        XCTAssertEqual(decodedTunnel.useIdentityFile, originalTunnel.useIdentityFile)
        XCTAssertEqual(decodedTunnel.identityFilePath, originalTunnel.identityFilePath)
        XCTAssertEqual(decodedTunnel.strictHostKeyChecking, originalTunnel.strictHostKeyChecking)
    }

    func testPasswordKeychainRoundTrip() {
        // Passwords are no longer stored on the struct — they live in the Keychain
        // under a per-tunnel key. Verify the round-trip and that the key is stable.
        let tunnel = SSHTunnel(name: "KC", sshServer: "example.com", username: "u")
        let key = tunnel.passwordKeychainKey
        XCTAssertTrue(key.hasPrefix("ssh-password-"))

        _ = KeychainHelper.shared.delete(forKey: key)
        defer { _ = KeychainHelper.shared.delete(forKey: key) }

        XCTAssertTrue(KeychainHelper.shared.save("s3cret", forKey: key))
        XCTAssertEqual(KeychainHelper.shared.get(forKey: key), "s3cret")
    }

    func testMigrationFromLegacyAutoConfigureProxy() throws {
        // Old saved tunnel JSON without proxyMode/selectiveHosts keys.
        let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "sshServer": "example.com",
          "port": 22,
          "username": "u",
          "localBindAddress": "localhost",
          "localPort": 8158,
          "autoConfigureProxy": true,
          "useIdentityFile": false,
          "identityFilePath": "",
          "strictHostKeyChecking": true,
          "serverAliveInterval": 30,
          "isConnected": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SSHTunnel.self, from: legacy)
        XCTAssertEqual(decoded.proxyMode, .all)
        XCTAssertTrue(decoded.selectiveHosts.isEmpty)
    }
    
    func testTunnelEquality() {
        let tunnel1 = SSHTunnel(
            name: "Test",
            sshServer: "example.com",
            port: 22,
            username: "user"
        )
        
        var tunnel2 = tunnel1
        XCTAssertEqual(tunnel1, tunnel2)
        
        tunnel2.name = "Different"
        XCTAssertNotEqual(tunnel1, tunnel2)
    }
    
    func testTunnelIdentifiable() {
        let tunnel1 = SSHTunnel(name: "Test1")
        let tunnel2 = SSHTunnel(name: "Test2")
        
        XCTAssertNotEqual(tunnel1.id, tunnel2.id)
    }
    
    func testTunnelWithIdentityFile() {
        let tunnel = SSHTunnel(
            name: "SSH Key Connection",
            sshServer: "example.com",
            username: "keyuser",
            useIdentityFile: true,
            identityFilePath: "~/.ssh/id_rsa"
        )
        
        XCTAssertTrue(tunnel.useIdentityFile)
        XCTAssertEqual(tunnel.identityFilePath, "~/.ssh/id_rsa")
    }
    
    func testTunnelCustomPort() {
        let tunnel = SSHTunnel(
            name: "Custom Port",
            sshServer: "example.com",
            port: 2222,
            username: "user",
            localPort: 9999
        )
        
        XCTAssertEqual(tunnel.port, 2222)
        XCTAssertEqual(tunnel.localPort, 9999)
    }
    
    func testTunnelWithoutHostKeyChecking() {
        let tunnel = SSHTunnel(
            name: "No Host Check",
            sshServer: "example.com",
            username: "user",
            strictHostKeyChecking: false
        )
        
        XCTAssertFalse(tunnel.strictHostKeyChecking)
    }
}
