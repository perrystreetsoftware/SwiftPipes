import XCTest
@testable import SwiftPipes

final class SSHTunnelTests: XCTestCase {
    
    func testTunnelInitialization() {
        let tunnel = SSHTunnel(
            name: "Test Connection",
            sshServer: "example.com",
            port: 22,
            username: "testuser",
            password: "testpass",
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
        XCTAssertEqual(tunnel.password, "testpass")
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
        XCTAssertEqual(tunnel.password, "")
        XCTAssertEqual(tunnel.localBindAddress, "localhost")
        XCTAssertEqual(tunnel.localPort, 8158)
        XCTAssertTrue(tunnel.autoConfigureProxy)
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
            password: "testpass",
            localBindAddress: "127.0.0.1",
            localPort: 9999,
            autoConfigureProxy: false,
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
        XCTAssertEqual(decodedTunnel.password, originalTunnel.password)
        XCTAssertEqual(decodedTunnel.localBindAddress, originalTunnel.localBindAddress)
        XCTAssertEqual(decodedTunnel.localPort, originalTunnel.localPort)
        XCTAssertEqual(decodedTunnel.autoConfigureProxy, originalTunnel.autoConfigureProxy)
        XCTAssertEqual(decodedTunnel.useIdentityFile, originalTunnel.useIdentityFile)
        XCTAssertEqual(decodedTunnel.identityFilePath, originalTunnel.identityFilePath)
        XCTAssertEqual(decodedTunnel.strictHostKeyChecking, originalTunnel.strictHostKeyChecking)
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
        XCTAssertEqual(tunnel.password, "")
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
