import SwiftUI
import AppKit

struct ManageConnectionsView: View {
    @EnvironmentObject var tunnelManager: SSHTunnelManager
    @State private var selectedTunnel: SSHTunnel?
    
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
                List(tunnelManager.tunnels, id: \.id, selection: $selectedTunnel) { tunnel in
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(tunnel.isConnected ? .green : .red)
                            .font(.system(size: 10))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tunnel.name)
                                .font(.headline)
                            Text("\(tunnel.username)@\(tunnel.sshServer):\(String(tunnel.port))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if tunnel.isConnected {
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
                        
                        Button("Delete", role: .destructive) {
                            tunnelManager.deleteTunnel(tunnel)
                            selectedTunnel = nil
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
                        tunnelManager.deleteTunnel(tunnel)
                        selectedTunnel = nil
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
}
