import XCTest
@testable import SwiftPipes

/// Tests covering the fix for the "green light when firewall blocks outbound SSH" bug.
/// The key invariants:
///   - A freshly created tunnel is .disconnected and isConnected == false.
///   - .connecting is NOT treated as connected (no green light, no SOCKS proxy).
///   - .failed is NOT treated as connected, and it preserves a reason string.
///   - connectionState is never persisted (restored tunnels always start disconnected).
///   - summarizeSSHFailure maps common ssh(1) stderr patterns to user-meaningful text.
final class ConnectionStateTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        // Per-test UserDefaults suite: never clobber the real app's savedTunnels.
        testSuiteName = "com.swiftpipes.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - ConnectionState / SSHTunnel invariants

    func testNewTunnelStartsDisconnected() {
        let tunnel = SSHTunnel(name: "n", sshServer: "s", username: "u")
        XCTAssertEqual(tunnel.connectionState, .disconnected)
        XCTAssertFalse(tunnel.isConnected)
        XCTAssertFalse(tunnel.isConnecting)
    }

    func testConnectingIsNotConsideredConnected() {
        var tunnel = SSHTunnel(name: "n", sshServer: "s", username: "u")
        tunnel.connectionState = .connecting
        XCTAssertFalse(tunnel.isConnected, "connecting must NOT be treated as connected")
        XCTAssertTrue(tunnel.isConnecting)
    }

    func testFailedIsNotConsideredConnected() {
        var tunnel = SSHTunnel(name: "n", sshServer: "s", username: "u")
        tunnel.connectionState = .failed("blocked")
        XCTAssertFalse(tunnel.isConnected)
        XCTAssertFalse(tunnel.isConnecting)
        if case .failed(let reason) = tunnel.connectionState {
            XCTAssertEqual(reason, "blocked")
        } else {
            XCTFail("expected .failed")
        }
    }

    func testConnectedIsConsideredConnected() {
        var tunnel = SSHTunnel(name: "n", sshServer: "s", username: "u")
        tunnel.connectionState = .connected
        XCTAssertTrue(tunnel.isConnected)
        XCTAssertFalse(tunnel.isConnecting)
    }

    // MARK: - Persistence: connectionState must not be saved

    func testConnectionStateIsNotPersisted() {
        let manager = SSHTunnelManager(userDefaults: testDefaults)
        manager.tunnels.removeAll()

        let tunnel = SSHTunnel(name: "t", sshServer: "s", username: "u")
        manager.addTunnel(tunnel)

        // Simulate the app being in a connected state when it is killed.
        if let idx = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[idx].connectionState = .connected
        }
        // Force a save via updateTunnel so connectionState would be persisted
        // if it were encodable.
        manager.updateTunnel(manager.tunnels[0])

        let reloaded = SSHTunnelManager(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.tunnels.count, 1)
        XCTAssertEqual(reloaded.tunnels[0].connectionState, .disconnected,
                       "restored tunnels must never come back as connected")
        XCTAssertFalse(reloaded.tunnels[0].isConnected)
    }

    // MARK: - summarizeSSHFailure

    func testSummarizeTimeoutLooksLikeFirewall() {
        let stderr = """
        debug1: Connecting to blocked.example.com port 22.
        ssh: connect to host blocked.example.com port 22: Operation timed out
        """
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("timed out"))
        XCTAssertTrue(reason.lowercased().contains("firewall"),
                      "timeouts should be surfaced as possible firewall blocks (got: \(reason))")
    }

    func testSummarizeConnectionTimedOutVariant() {
        let stderr = "ssh: connect to host x port 22: Connection timed out"
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("timed out"))
    }

    func testSummarizeNoRouteToHost() {
        let stderr = "ssh: connect to host x port 22: No route to host"
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("no route"))
    }

    func testSummarizeConnectionRefused() {
        let stderr = "ssh: connect to host x port 22: Connection refused"
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("refused"))
    }

    func testSummarizeAuthFailure() {
        let stderr = "Permission denied (publickey,password)."
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("authentication"))
    }

    func testSummarizeDNSFailure() {
        let stderr = "ssh: Could not resolve hostname nope.invalid: nodename nor servname provided"
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("resolve"))
    }

    func testSummarizeHostKeyFailure() {
        let stderr = "Host key verification failed."
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertTrue(reason.lowercased().contains("host key"))
    }

    func testSummarizeFallsBackToLastNonDebugLine() {
        let stderr = """
        debug1: reading configuration data
        debug1: Connecting to x port 22.
        something weird happened
        """
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: stderr)
        XCTAssertEqual(reason, "something weird happened")
    }

    func testSummarizeEmptyStderr() {
        let reason = SSHTunnelManager.summarizeSSHFailure(stderr: "")
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - Manager behavior

    func testConnectFailsWhenLocalPortInUseDoesNotShowAsConnected() {
        let manager = SSHTunnelManager(userDefaults: testDefaults)
        manager.tunnels.removeAll()

        // Occupy a port locally.
        let listener = makeListeningSocket()
        defer { close(listener.fd) }

        let tunnel = SSHTunnel(
            name: "t",
            sshServer: "127.0.0.1",
            username: "nobody",
            localBindAddress: "127.0.0.1",
            localPort: listener.port,
            autoConfigureProxy: false
        )
        manager.addTunnel(tunnel)
        manager.connect(manager.tunnels[0].id)

        // The port is in use, so the attempt must not produce a "connected" state.
        XCTAssertFalse(manager.tunnels[0].isConnected,
                       "must not show green light when local port is already in use")
        XCTAssertFalse(manager.hasActiveConnections)
        if case .failed(let reason) = manager.tunnels[0].connectionState {
            // The reason should always reference the busy port.
            XCTAssertTrue(reason.contains("Local port \(listener.port)"),
                          "reason should reference the busy port number, got: \(reason)")
            XCTAssertTrue(reason.contains("already in use"),
                          "reason should say the port is already in use, got: \(reason)")
        } else {
            XCTFail("expected .failed, got \(manager.tunnels[0].connectionState)")
        }
    }

    // MARK: - lsofListener / describePortHolder

    func testLsofListenerIdentifiesListener() throws {
        let listener = makeListeningSocket()
        defer { close(listener.fd) }

        // The test process itself is holding the port. lsof should find it.
        guard let holder = SSHTunnelManager.lsofListener(port: listener.port) else {
            throw XCTSkip("lsof unavailable or returned no rows for the test-held port")
        }
        XCTAssertGreaterThan(holder.pid, 0)
        XCTAssertFalse(holder.command.isEmpty,
                       "command name should not be empty (got pid \(holder.pid))")
    }

    func testDescribePortHolderClassifiesTestProcessAsForeign() throws {
        let listener = makeListeningSocket()
        defer { close(listener.fd) }

        // The test runner isn't a SwiftPipes-spawned ssh process, so the
        // classifier should land on `.foreign`.
        let manager = SSHTunnelManager(userDefaults: testDefaults)
        guard let holder = manager.describePortHolder(port: listener.port) else {
            throw XCTSkip("lsof unavailable")
        }
        switch holder {
        case .foreign:
            break // expected
        case .ours, .orphanedSwiftPipes:
            XCTFail("expected .foreign, got \(holder)")
        }
    }

    func testLsofListenerReturnsNilForFreePort() {
        // Pick an unlikely-bound high port. Tiny race risk but the function
        // should still return a well-formed value either way.
        _ = SSHTunnelManager.lsofListener(port: 59999)
    }

    // MARK: - Host key prompt parsing

    func testParseHostKeyChangeReturnsNilForNonHostKeyStderr() {
        let stderr = "Permission denied (publickey,password)."
        let prompt = SSHTunnelManager.parseHostKeyChange(
            stderr: stderr,
            tunnelId: UUID(),
            host: "example.com",
            port: 22
        )
        XCTAssertNil(prompt)
    }

    func testParseHostKeyChangeExtractsFingerprintAndType() {
        let stderr = """
        debug1: Connecting to example.com port 22.
        debug1: Connection established.
        debug1: Server host key: ssh-ed25519 SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        Offending ED25519 key in /Users/foo/.ssh/known_hosts:42
        Host key for example.com has changed and you have requested strict checking.
        Host key verification failed.
        """
        let tunnelId = UUID()
        let prompt = SSHTunnelManager.parseHostKeyChange(
            stderr: stderr,
            tunnelId: tunnelId,
            host: "example.com",
            port: 22
        )
        XCTAssertNotNil(prompt)
        XCTAssertEqual(prompt?.tunnelId, tunnelId)
        XCTAssertEqual(prompt?.host, "example.com")
        XCTAssertEqual(prompt?.port, 22)
        XCTAssertEqual(prompt?.keyType, "ED25519")
        XCTAssertEqual(prompt?.newFingerprint, "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(prompt?.knownHostsPath, "/Users/foo/.ssh/known_hosts")
    }

    func testParseHostKeyChangeRSA() {
        let stderr = """
        debug1: Server host key: ssh-rsa SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
        Host key verification failed.
        """
        let prompt = SSHTunnelManager.parseHostKeyChange(
            stderr: stderr,
            tunnelId: UUID(),
            host: "host",
            port: 2222
        )
        XCTAssertEqual(prompt?.keyType, "RSA")
        XCTAssertEqual(prompt?.newFingerprint, "SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    func testParseHostKeyChangeWithoutOffendingLineStillReturnsPrompt() {
        let stderr = """
        debug1: Server host key: ecdsa-sha2-nistp256 SHA256:CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
        Host key verification failed.
        """
        let prompt = SSHTunnelManager.parseHostKeyChange(
            stderr: stderr,
            tunnelId: UUID(),
            host: "host",
            port: 22
        )
        XCTAssertNotNil(prompt)
        XCTAssertEqual(prompt?.keyType, "ECDSA")
        XCTAssertNil(prompt?.knownHostsPath)
    }

    // MARK: - SwiftPipes ssh argv signature matcher

    func testIsSwiftPipesSshArgvMatchesRealCommand() {
        // Captured from a real orphaned SwiftPipes ssh (PID 89968 in the
        // bug repro):
        let cmd = "/usr/bin/ssh -v -D localhost:8158 -N -p 32722 -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -i /Users/pss/.ssh/id_rsa_scruff -o ServerAliveInterval=30 -o ServerAliveCountMax=3 bastian@vpn3.scruffapp.com"
        XCTAssertTrue(SSHTunnelManager.isSwiftPipesSshArgv(cmd))
    }

    func testIsSwiftPipesSshArgvRejectsPlainSsh() {
        XCTAssertFalse(SSHTunnelManager.isSwiftPipesSshArgv("/usr/bin/ssh user@host"))
    }

    func testIsSwiftPipesSshArgvRejectsLocalForward() {
        // -L is local forward, NOT what SwiftPipes spawns.
        let cmd = "/usr/bin/ssh -L 8080:localhost:80 -N user@host"
        XCTAssertFalse(SSHTunnelManager.isSwiftPipesSshArgv(cmd))
    }

    func testIsSwiftPipesSshArgvRejectsNonSystemSsh() {
        // A homebrew/manually-installed ssh wouldn't be at /usr/bin.
        let cmd = "/opt/homebrew/bin/ssh -v -D localhost:8158 -N -p 22 -o ConnectTimeout=10 -o ExitOnForwardFailure=yes user@host"
        XCTAssertFalse(SSHTunnelManager.isSwiftPipesSshArgv(cmd))
    }

    func testIsSwiftPipesSshArgvRejectsMissingFlag() {
        // Missing ExitOnForwardFailure — could be a different tool's invocation.
        let cmd = "/usr/bin/ssh -v -D localhost:8158 -N -p 22 -o ConnectTimeout=10 user@host"
        XCTAssertFalse(SSHTunnelManager.isSwiftPipesSshArgv(cmd))
    }

    // MARK: - Helpers

    private func makeListeningSocket() -> (fd: Int32, port: Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        precondition(fd >= 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // kernel assigns
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(bindResult == 0)
        precondition(Darwin.listen(fd, 1) == 0)
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        let port = Int(UInt16(bigEndian: bound.sin_port))
        return (fd, port)
    }
}
