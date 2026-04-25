import SwiftUI
import AppKit

struct ManageConnectionsView: View {
    @EnvironmentObject var tunnelManager: SSHTunnelManager
    @State private var selectedTunnelID: UUID?
    private var selectedTunnel: SSHTunnel? { tunnelManager.tunnels.first { $0.id == selectedTunnelID } }

    var body: some View {
        VStack(spacing: 0) {
            if tunnelManager.tunnels.isEmpty {
                VStack {
                    Spacer()
                    Text("No Connections")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Click + to add a new connection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(tunnelManager.tunnels, id: \.id, selection: $selectedTunnelID) { tunnel in
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(statusColor(for: tunnel.connectionState))
                            .font(.system(size: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tunnel.name)
                                .font(.headline)
                            Text("\(tunnel.username)@\(tunnel.sshServer):\(String(tunnel.port))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if case .failed(let reason) = tunnel.connectionState {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            } else if case .connecting = tunnel.connectionState {
                                Text("Connecting…")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        Button(tunnel.isConnected || tunnel.isConnecting ? "Disconnect" : "Connect") {
                            if tunnel.isConnected || tunnel.isConnecting {
                                tunnelManager.disconnect(tunnel.id)
                            } else {
                                tunnelManager.connect(tunnel.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if tunnel.isConnected || tunnel.isConnecting {
                            Button("Disconnect") {
                                tunnelManager.disconnect(tunnel.id)
                            }
                        } else {
                            Button("Connect") {
                                tunnelManager.connect(tunnel.id)
                            }
                        }

                        Divider()

                        Button("Edit...") {
                            showConnectionEditor(for: tunnel)
                        }

                        Button("Duplicate") {
                            let copy = tunnelManager.duplicateTunnel(tunnel)
                            selectedTunnelID = copy.id
                        }

                        Button("Delete", role: .destructive) {
                            tunnelManager.deleteTunnel(tunnel)
                            selectedTunnelID = nil
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: {
                    showConnectionEditor(for: SSHTunnel())
                }) {
                    Image(systemName: "plus")
                }
                .help("Add Connection")

                Button(action: {
                    if let tunnel = selectedTunnel {
                        showConnectionEditor(for: tunnel)
                    }
                }) {
                    Image(systemName: "pencil")
                }
                .disabled(selectedTunnel == nil)
                .help("Edit Connection")

                Button(action: {
                    if let tunnel = selectedTunnel {
                        selectedTunnelID = tunnelManager.duplicateTunnel(tunnel).id
                    }
                }) {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selectedTunnel == nil)
                .help("Duplicate Connection")

                Button(action: {
                    if let tunnel = selectedTunnel {
                        tunnelManager.deleteTunnel(tunnel)
                        selectedTunnelID = nil
                    }
                }) {
                    Image(systemName: "trash")
                }
                .disabled(selectedTunnel == nil)
                .help("Delete Connection")

                Spacer()

                Button("Done") {
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private func showConnectionEditor(for tunnel: SSHTunnel) {
        let editorView = ConnectionEditorView(tunnel: tunnel) { updatedTunnel in
            if tunnelManager.tunnels.contains(where: { $0.id == updatedTunnel.id }) {
                tunnelManager.updateTunnel(updatedTunnel)
            } else {
                tunnelManager.addTunnel(updatedTunnel)
            }
        }

        let hostingController = NSHostingController(rootView: editorView.environmentObject(tunnelManager))

        let window = NSWindow(contentViewController: hostingController)
        window.title = tunnel.name.isEmpty ? "New Connection" : "Edit Connection"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        }
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }
}
