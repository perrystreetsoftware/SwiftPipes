import XCTest
@testable import SwiftPipes

final class SSHTunnelManagerTests: XCTestCase {
    
    var manager: SSHTunnelManager!
    var testDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        // Use a throwaway UserDefaults suite per test so we never touch the app's
        // real prefs domain (com.swiftpipes.app) when tests run on a developer machine.
        testSuiteName = "com.swiftpipes.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        manager = SSHTunnelManager(userDefaults: testDefaults)
        manager.tunnels.removeAll()
    }

    override func tearDown() {
        for tunnel in manager.tunnels where tunnel.isConnected {
            manager.disconnect(tunnel.id)
        }
        testDefaults.removePersistentDomain(forName: testSuiteName)
        manager = nil
        testDefaults = nil
        testSuiteName = nil
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
        
        let newManager = SSHTunnelManager(userDefaults: testDefaults)
        
        XCTAssertEqual(newManager.tunnels.count, 2)
        XCTAssertEqual(newManager.tunnels[0].name, "Persistent 1")
        XCTAssertEqual(newManager.tunnels[1].name, "Persistent 2")
        
        for tunnel in newManager.tunnels {
            XCTAssertFalse(tunnel.isConnected)
        }
    }
    
    func testHasActiveConnection() {
        XCTAssertFalse(manager.hasActiveConnection)
        
        let tunnel = SSHTunnel(name: "Test", sshServer: "example.com", username: "user")
        manager.addTunnel(tunnel)
        
        XCTAssertFalse(manager.hasActiveConnection)
        
        if let index = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[index].connectionState = .connected
        }
        
        XCTAssertTrue(manager.hasActiveConnection)
    }
    
    func testHasActiveConnections() {
        XCTAssertFalse(manager.hasActiveConnections)
        
        let tunnel = SSHTunnel(name: "Test", sshServer: "example.com", username: "user")
        manager.addTunnel(tunnel)
        
        XCTAssertFalse(manager.hasActiveConnections)
        
        if let index = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[index].connectionState = .connected
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
            localBindAddress: "127.0.0.1",
            localPort: 9999,
            autoConfigureProxy: false,
            useIdentityFile: true,
            identityFilePath: "/path/to/key",
            strictHostKeyChecking: false
        )

        manager.addTunnel(tunnel)

        let newManager = SSHTunnelManager(userDefaults: testDefaults)

        XCTAssertEqual(newManager.tunnels.count, 1)
        let loaded = newManager.tunnels[0]

        XCTAssertEqual(loaded.name, "Complete Tunnel")
        XCTAssertEqual(loaded.sshServer, "example.com")
        XCTAssertEqual(loaded.port, 2222)
        XCTAssertEqual(loaded.username, "testuser")
        XCTAssertEqual(loaded.localBindAddress, "127.0.0.1")
        XCTAssertEqual(loaded.localPort, 9999)
        XCTAssertEqual(loaded.autoConfigureProxy, false)
        XCTAssertEqual(loaded.useIdentityFile, true)
        XCTAssertEqual(loaded.identityFilePath, "/path/to/key")
        XCTAssertEqual(loaded.strictHostKeyChecking, false)
        XCTAssertFalse(loaded.isConnected)
    }
}

final class ProxyRuleTests: XCTestCase {

    func testParseBareDomain() {
        XCTAssertEqual(ProxyRule.parse("www.example.com"), .domain("www.example.com"))
    }

    func testParseWildcardDomain() {
        XCTAssertEqual(ProxyRule.parse("*.example.com"), .domain("*.example.com"))
    }

    func testParseIPv4() {
        XCTAssertEqual(ProxyRule.parse("10.0.0.5"), .ipv4("10.0.0.5"))
    }

    func testParseIPv4CIDR() {
        XCTAssertEqual(
            ProxyRule.parse("192.168.1.0/24"),
            .ipv4CIDR(net: "192.168.1.0", mask: "255.255.255.0")
        )
    }

    func testParseIPv4CIDRSlash16() {
        XCTAssertEqual(
            ProxyRule.parse("10.0.0.0/16"),
            .ipv4CIDR(net: "10.0.0.0", mask: "255.255.0.0")
        )
    }

    func testParseIPv4CIDRSlash32() {
        XCTAssertEqual(
            ProxyRule.parse("10.0.0.5/32"),
            .ipv4CIDR(net: "10.0.0.5", mask: "255.255.255.255")
        )
    }

    func testParseEmptyReturnsNil() {
        XCTAssertNil(ProxyRule.parse(""))
        XCTAssertNil(ProxyRule.parse("   "))
    }

    func testParseInvalidCIDRBitsReturnsNil() {
        XCTAssertNil(ProxyRule.parse("10.0.0.0/33"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(ProxyRule.parse("  www.example.com  "), .domain("www.example.com"))
    }
}

final class PACGeneratorTests: XCTestCase {

    func testEmptyRulesYieldsDirectFallback() {
        let pac = PACGenerator.makePAC(proxyHost: "127.0.0.1", proxyPort: 8158, rules: [])
        XCTAssertTrue(pac.contains("function FindProxyForURL"))
        XCTAssertTrue(pac.contains("return \"DIRECT\""))
        XCTAssertFalse(pac.contains("shExpMatch"))
        XCTAssertFalse(pac.contains("isInNet"))
    }

    func testDomainRuleEmitsShExpMatch() {
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 8158,
            rules: [.domain("www.example.com")]
        )
        XCTAssertTrue(pac.contains("shExpMatch(host, \"www.example.com\")"))
        XCTAssertTrue(pac.contains("SOCKS 127.0.0.1:8158"))
        XCTAssertTrue(pac.contains("SOCKS5 127.0.0.1:8158"))
    }

    func testWildcardDomainPassesThrough() {
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 8158,
            rules: [.domain("*.example.com")]
        )
        XCTAssertTrue(pac.contains("shExpMatch(host, \"*.example.com\")"))
    }

    func testIPv4RuleEmitsEqualityCheck() {
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 8158,
            rules: [.ipv4("10.0.0.5")]
        )
        XCTAssertTrue(pac.contains("host == \"10.0.0.5\""))
    }

    func testCIDRRuleEmitsIsInNet() {
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 8158,
            rules: [.ipv4CIDR(net: "192.168.1.0", mask: "255.255.255.0")]
        )
        XCTAssertTrue(pac.contains("isInNet(host, \"192.168.1.0\", \"255.255.255.0\")"))
    }

    func testMixedRulesAllAppear() {
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 1080,
            rules: [
                .domain("www.example.com"),
                .domain("*.internal"),
                .ipv4("8.8.8.8"),
                .ipv4CIDR(net: "10.0.0.0", mask: "255.0.0.0")
            ]
        )
        XCTAssertTrue(pac.contains("shExpMatch(host, \"www.example.com\")"))
        XCTAssertTrue(pac.contains("shExpMatch(host, \"*.internal\")"))
        XCTAssertTrue(pac.contains("host == \"8.8.8.8\""))
        XCTAssertTrue(pac.contains("isInNet(host, \"10.0.0.0\", \"255.0.0.0\")"))
        XCTAssertTrue(pac.contains("return \"DIRECT\""))
    }

    func testEscapesDoubleQuotesInDomain() {
        // Defensive: a malformed rule shouldn't break out of the JS string literal.
        let pac = PACGenerator.makePAC(
            proxyHost: "127.0.0.1",
            proxyPort: 8158,
            rules: [.domain("bad\"host")]
        )
        XCTAssertTrue(pac.contains("shExpMatch(host, \"bad\\\"host\")"))
    }
}
