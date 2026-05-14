import XCTest
@testable import SwiftPipes

final class DuplicateTunnelTests: XCTestCase {

    var manager: SSHTunnelManager!
    var testDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        // Per-test throwaway UserDefaults suite so we NEVER touch the real app
        // prefs domain (com.perrystreet.swiftpipes) when running on a dev machine.
        testSuiteName = "com.swiftpipes.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        manager = SSHTunnelManager(userDefaults: testDefaults)
        manager.tunnels.removeAll()
    }

    override func tearDown() {
        // Clean up any keychain entries created during tests.
        for tunnel in manager.tunnels {
            _ = KeychainHelper.shared.delete(forKey: tunnel.passwordKeychainKey)
        }
        testDefaults.removePersistentDomain(forName: testSuiteName)
        manager = nil
        testDefaults = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - Basic duplication

    func testDuplicateProducesCopyWithNewId() {
        let original = SSHTunnel(
            name: "Prod",
            sshServer: "prod.example.com",
            port: 2222,
            username: "admin",
            localBindAddress: "127.0.0.1",
            localPort: 9000,
            autoConfigureProxy: false,
            useIdentityFile: true,
            identityFilePath: "~/.ssh/id_ed25519",
            strictHostKeyChecking: false,
            serverAliveInterval: 45
        )
        manager.addTunnel(original)

        let copy = manager.duplicateTunnel(manager.tunnels[0])

        XCTAssertNotEqual(copy.id, original.id, "duplicate must have a fresh id")
        XCTAssertEqual(copy.sshServer, original.sshServer)
        XCTAssertEqual(copy.port, original.port)
        XCTAssertEqual(copy.username, original.username)
        XCTAssertEqual(copy.localBindAddress, original.localBindAddress)
        XCTAssertEqual(copy.localPort, original.localPort)
        XCTAssertEqual(copy.autoConfigureProxy, original.autoConfigureProxy)
        XCTAssertEqual(copy.useIdentityFile, original.useIdentityFile)
        XCTAssertEqual(copy.identityFilePath, original.identityFilePath)
        XCTAssertEqual(copy.strictHostKeyChecking, original.strictHostKeyChecking)
        XCTAssertEqual(copy.serverAliveInterval, original.serverAliveInterval)
    }

    func testDuplicateIsInsertedAfterSource() {
        let a = SSHTunnel(name: "A", sshServer: "a", username: "u")
        let b = SSHTunnel(name: "B", sshServer: "b", username: "u")
        let c = SSHTunnel(name: "C", sshServer: "c", username: "u")
        manager.addTunnel(a)
        manager.addTunnel(b)
        manager.addTunnel(c)

        let copy = manager.duplicateTunnel(manager.tunnels[1]) // duplicate "B"

        XCTAssertEqual(manager.tunnels.count, 4)
        XCTAssertEqual(manager.tunnels.map { $0.name }, ["A", "B", copy.name, "C"])
    }

    func testDuplicateStartsDisconnectedEvenIfSourceWasConnected() {
        var tunnel = SSHTunnel(name: "Live", sshServer: "s", username: "u")
        manager.addTunnel(tunnel)
        manager.tunnels[0].connectionState = .connected
        tunnel = manager.tunnels[0]

        let copy = manager.duplicateTunnel(tunnel)

        XCTAssertEqual(copy.connectionState, .disconnected)
        XCTAssertFalse(copy.isConnected)
    }

    // MARK: - Name collision handling

    func testDuplicateAppendsCopySuffix() {
        manager.addTunnel(SSHTunnel(name: "Foo", sshServer: "s", username: "u"))
        let copy = manager.duplicateTunnel(manager.tunnels[0])
        XCTAssertEqual(copy.name, "Foo Copy")
    }

    func testDuplicateAvoidsNameCollisions() {
        manager.addTunnel(SSHTunnel(name: "Foo", sshServer: "s", username: "u"))

        let copy1 = manager.duplicateTunnel(manager.tunnels[0])
        XCTAssertEqual(copy1.name, "Foo Copy")

        let copy2 = manager.duplicateTunnel(manager.tunnels[0])
        XCTAssertEqual(copy2.name, "Foo Copy 2")

        let copy3 = manager.duplicateTunnel(manager.tunnels[0])
        XCTAssertEqual(copy3.name, "Foo Copy 3")
    }

    func testDuplicateHandlesEmptyName() {
        manager.addTunnel(SSHTunnel(name: "", sshServer: "s", username: "u"))
        let copy = manager.duplicateTunnel(manager.tunnels[0])
        XCTAssertEqual(copy.name, "Connection Copy")
    }

    // MARK: - Persistence

    func testDuplicateIsPersisted() {
        manager.addTunnel(SSHTunnel(name: "Orig", sshServer: "s", username: "u"))
        _ = manager.duplicateTunnel(manager.tunnels[0])

        let reloaded = SSHTunnelManager(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.tunnels.count, 2)
        XCTAssertEqual(reloaded.tunnels.map { $0.name }, ["Orig", "Orig Copy"])
        XCTAssertNotEqual(reloaded.tunnels[0].id, reloaded.tunnels[1].id)
    }

    // MARK: - Keychain

    func testDuplicateCopiesPasswordInKeychain() {
        let original = SSHTunnel(name: "KC", sshServer: "s", username: "u")
        manager.addTunnel(original)
        defer {
            _ = KeychainHelper.shared.delete(forKey: original.passwordKeychainKey)
        }

        XCTAssertTrue(KeychainHelper.shared.save("hunter2", forKey: original.passwordKeychainKey))

        let copy = manager.duplicateTunnel(manager.tunnels[0])
        defer {
            _ = KeychainHelper.shared.delete(forKey: copy.passwordKeychainKey)
        }

        XCTAssertNotEqual(copy.passwordKeychainKey, original.passwordKeychainKey)
        XCTAssertEqual(KeychainHelper.shared.get(forKey: copy.passwordKeychainKey), "hunter2")
        // Original password must be untouched.
        XCTAssertEqual(KeychainHelper.shared.get(forKey: original.passwordKeychainKey), "hunter2")
    }

    func testDuplicateWithoutSourcePasswordDoesNotCreateKeychainEntry() {
        let original = SSHTunnel(name: "NoPass", sshServer: "s", username: "u")
        manager.addTunnel(original)
        // Ensure no password is stored for the source.
        _ = KeychainHelper.shared.delete(forKey: original.passwordKeychainKey)

        let copy = manager.duplicateTunnel(manager.tunnels[0])
        defer { _ = KeychainHelper.shared.delete(forKey: copy.passwordKeychainKey) }

        XCTAssertNil(KeychainHelper.shared.get(forKey: copy.passwordKeychainKey))
    }

    // MARK: - Isolation

    func testMutatingDuplicateDoesNotAffectOriginal() {
        manager.addTunnel(SSHTunnel(name: "Orig", sshServer: "a.example.com", username: "u"))
        var copy = manager.duplicateTunnel(manager.tunnels[0])
        copy.sshServer = "b.example.com"
        copy.port = 2200
        manager.updateTunnel(copy)

        let original = manager.tunnels.first { $0.name == "Orig" }
        XCTAssertEqual(original?.sshServer, "a.example.com")
        XCTAssertEqual(original?.port, 22)

        let duplicated = manager.tunnels.first { $0.name == "Orig Copy" }
        XCTAssertEqual(duplicated?.sshServer, "b.example.com")
        XCTAssertEqual(duplicated?.port, 2200)
    }

    func testDeletingDuplicateDoesNotDeleteOriginalKeychainEntry() {
        let original = SSHTunnel(name: "Keep", sshServer: "s", username: "u")
        manager.addTunnel(original)
        defer { _ = KeychainHelper.shared.delete(forKey: original.passwordKeychainKey) }
        XCTAssertTrue(KeychainHelper.shared.save("keepme", forKey: original.passwordKeychainKey))

        let copy = manager.duplicateTunnel(manager.tunnels[0])
        manager.deleteTunnel(copy)

        XCTAssertEqual(KeychainHelper.shared.get(forKey: original.passwordKeychainKey), "keepme",
                       "deleting the duplicate must not affect the source's keychain entry")
    }
}
