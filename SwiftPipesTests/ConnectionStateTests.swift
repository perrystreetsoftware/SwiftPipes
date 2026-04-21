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
        UserDefaults.standard.removeObject(forKey: "savedTunnels")
        defer { UserDefaults.standard.removeObject(forKey: "savedTunnels") }

        let manager = SSHTunnelManager()
        manager.tunnels.removeAll()

        let tunnel = SSHTunnel(name: "t", sshServer: "s", username: "u")
        manager.addTunnel(tunnel)

        // Simulate the app being in a connected state when it is killed.
        if let idx = manager.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            manager.tunnels[idx].connectionState = .connected
        }
        // Re-save so the "connected" state would be persisted if it were encodable.
        manager.tunnels = manager.tunnels // no-op, but trigger nothing special
        // addTunnel already called saveTunnels() above, which is what persists. The
        // key is: even if connectionState were encoded, loadTunnels should reset it.
        // Force a save by re-adding via updateTunnel path:
        manager.updateTunnel(manager.tunnels[0])

        let reloaded = SSHTunnelManager()
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
        UserDefaults.standard.removeObject(forKey: "savedTunnels")
        defer { UserDefaults.standard.removeObject(forKey: "savedTunnels") }

        let manager = SSHTunnelManager()
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
        if case .failed = manager.tunnels[0].connectionState {
            // ok
        } else {
            XCTFail("expected .failed, got \(manager.tunnels[0].connectionState)")
        }
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
