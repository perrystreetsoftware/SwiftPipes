import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var tunnelManager: SSHTunnelManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tunnelManager.tunnels.isEmpty {
                Text("No connections configured")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach($tunnelManager.tunnels) { $tunnel in
                    Button(action: {
                        tunnelManager.toggleConnection(tunnel.id)
                    }) {
                        HStack {
                            statusIcon(for: tunnel.connectionState)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tunnel.name)
                                if case .failed(let reason) = tunnel.connectionState {
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                        .lineLimit(2)
                                } else if case .connecting = tunnel.connectionState {
                                    Text("Connecting…")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Edit...") {
                            showConnectionEditor(for: tunnel)
                        }
                        Button("Delete", role: .destructive) {
                            tunnelManager.deleteTunnel(tunnel)
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Manage Connections...") {
                showManageConnections()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Button("Preferences...") {
                showPreferences()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            Divider()
            
            Button("Quit SwiftPipes") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 250)
    }

    @ViewBuilder
    private func statusIcon(for state: ConnectionState) -> some View {
        switch state {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .connecting:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundColor(.yellow)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        case .disconnected:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
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
    
    private func showManageConnections() {
        let manageView = ManageConnectionsView()
            .environmentObject(tunnelManager)
        
        let hostingController = NSHostingController(rootView: manageView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Manage Connections"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showPreferences() {
        let preferencesView = PreferencesView()
        
        let hostingController = NSHostingController(rootView: preferencesView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        
        NSApp.activate(ignoringOtherApps: true)
    }
}
