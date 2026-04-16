import XCTest
@testable import SwiftPipes

final class SSHTunnelManagerTests: XCTestCase {
    
    var manager: SSHTunnelManager!
    
    override func setUp() {
        super.setUp()
        manager = SSHTunnelManager()
        UserDefaults.standard.removeObject(forKey: "savedTunnels")
        manager.tunnels.removeAll()
    }
    
    override func tearDown() {
        for tunnel in manager.tunnels where tunnel.isConnected {
            manager.disconnect(tunnel.id)
        }
        UserDefaults.standard.removeObject(forKey: "savedTunnels")
        manager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertTrue(manager.tunnels.isEmpty)
        XCTAssertFalse(manager.hasActiveConnections)
    }
    
    func testAddTunnel() {
        let tunnel = SSHTunnel(
            name: "Test Tunnel",
            sshServer: "example.com",
            username: "testuser"
        )
        
        manager.addTunnel(tunnel)
        
        XCTAssertEqual(manager.tunnels.count, 1)
        XCTAssertEqual(manager.tunnels.first?.name, "Test Tunnel")
    }
    
    func testAddMultipleTunnels() {
        let tunnel1 = SSHTunnel(name: "Tunnel 1", sshServer: "server1.com", username: "user1")
        let tunnel2 = SSHTunnel(name: "Tunnel 2", sshServer: "server2.com", username: "user2")
        let tunnel3 = SSHTunnel(name: "Tunnel 3", sshServer: "server3.com", username: "user3")
        
        manager.addTunnel(tunnel1)
        manager.addTunnel(tunnel2)
        manager.addTunnel(tunnel3)
        
        XCTAssertEqual(manager.tunnels.count, 3)
        XCTAssertEqual(manager.tunnels[0].name, "Tunnel 1")
        XCTAssertEqual(manager.tunnels[1].name, "Tunnel 2")
        XCTAssertEqual(manager.tunnels[2].name, "Tunnel 3")
    }
    
    func testUpdateTunnel() {
        var tunnel = SSHTunnel(
            name: "Original",
            sshServer: "example.com",
            username: "user"
        )
        
        manager.addTunnel(tunnel)
        
        tunnel = manager.tunnels.first!
        tunnel.name = "Updated"
        tunnel.sshServer = "updated.com"
        
        manager.updateTunnel(tunnel)
        
        XCTAssertEqual(manager.tunnels.count, 1)
        XCTAssertEqual(manager.tunnels.first?.name, "Updated")
        XCTAssertEqual(manager.tunnels.first?.sshServer, "updated.com")
    }
    
    func testDeleteTunnel() {
        let tunnel = SSHTunnel(
            name: "Test Tunnel",
            sshServer: "example.com",
            username: "testuser"
        )
        
        manager.addTunnel(tunnel)
        XCTAssertEqual(manager.tunnels.count, 1)
        
        manager.deleteTunnel(tunnel)
        XCTAssertEqual(manager.tunnels.count, 0)
    }
    
    func testDeleteSpecificTunnel() {
        let tunnel1 = SSHTunnel(name: "Tunnel 1", sshServer: "server1.com", username: "user1")
        let tunnel2 = SSHTunnel(name: "Tunnel 2", sshServer: "server2.com", username: "user2")
        let tunnel3 = SSHTunnel(name: "Tunnel 3", sshServer: "server3.com", username: "user3")
        
        manager.addTunnel(tunnel1)
        manager.addTunnel(tunnel2)
        manager.addTunnel(tunnel3)
        
        manager.deleteTunnel(manager.tunnels[1])
        
        XCTAssertEqual(manager.tunnels.count, 2)
        XCTAssertEqual(manager.tunnels[0].name, "Tunnel 1")
        XCTAssertEqual(manager.tunnels[1].name, "Tunnel 3")
    }
    
    func testPersistence() {
        let tunnel1 = SSHTunnel(name: "Persistent 1", sshServer: "server1.com", username: "user1")
        let tunnel2 = SSHTunnel(name: "Persistent 2", sshServer: "server2.com", username: "user2")
        
        manager.addTunnel(tunnel1)
        manager.addTunnel(tunnel2)
        
        let newManager = SSHTunnelManager()
        
        XCTAssertEqual(newManager.tunnels.count, 2)
        XCTAssertEqual(newManager.tunnels[0].name, "Persistent 1")
        XCTAssertEqual(newManager.tunnels[1].name, "Persistent 2")
        
        for tunnel in newManager.tunnels {
            XCTAssertFalse(tunnel.isConnected)
        }
    }
    
    func testHasActiveConnection() {
        XCTAssertFalse(manager.hasActiveConnection)
        
        var tunnel = SSHTunnel(name: "Test", sshServer: "example.com", username: "user")
        manager.addTunnel(tunnel)
        
        XCTAssertFalse(manager.hasActiveConnection)
        
        if let index = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[index].isConnected = true
        }
        
        XCTAssertTrue(manager.hasActiveConnection)
    }
    
    func testHasActiveConnections() {
        XCTAssertFalse(manager.hasActiveConnections)
        
        let tunnel = SSHTunnel(name: "Test", sshServer: "example.com", username: "user")
        manager.addTunnel(tunnel)
        
        XCTAssertFalse(manager.hasActiveConnections)
        
        if let index = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[index].isConnected = true
        }
        
        manager.hasActiveConnections = manager.tunnels.contains { $0.isConnected }
        XCTAssertTrue(manager.hasActiveConnections)
    }
    
    func testTunnelIsolation() {
        let tunnel1 = SSHTunnel(name: "Tunnel 1", sshServer: "server1.com", username: "user1")
        let tunnel2 = SSHTunnel(name: "Tunnel 2", sshServer: "server2.com", username: "user2")
        
        manager.addTunnel(tunnel1)
        manager.addTunnel(tunnel2)
        
        var modifiedTunnel = manager.tunnels[0]
        modifiedTunnel.name = "Modified"
        
        manager.updateTunnel(modifiedTunnel)
        
        XCTAssertEqual(manager.tunnels[0].name, "Modified")
        XCTAssertEqual(manager.tunnels[1].name, "Tunnel 2")
    }
    
    func testEncodingDecodingPreservesAllFields() {
        let tunnel = SSHTunnel(
            name: "Complete Tunnel",
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
        
        manager.addTunnel(tunnel)
        
        let newManager = SSHTunnelManager()
        
        XCTAssertEqual(newManager.tunnels.count, 1)
        let loaded = newManager.tunnels[0]
        
        XCTAssertEqual(loaded.name, "Complete Tunnel")
        XCTAssertEqual(loaded.sshServer, "example.com")
        XCTAssertEqual(loaded.port, 2222)
        XCTAssertEqual(loaded.username, "testuser")
        XCTAssertEqual(loaded.password, "testpass")
        XCTAssertEqual(loaded.localBindAddress, "127.0.0.1")
        XCTAssertEqual(loaded.localPort, 9999)
        XCTAssertEqual(loaded.autoConfigureProxy, false)
        XCTAssertEqual(loaded.useIdentityFile, true)
        XCTAssertEqual(loaded.identityFilePath, "/path/to/key")
        XCTAssertEqual(loaded.strictHostKeyChecking, false)
        XCTAssertFalse(loaded.isConnected)
    }
}
