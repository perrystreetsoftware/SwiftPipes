import SwiftUI
import AppKit

struct ConnectionEditorView: View {
    @State private var tunnel: SSHTunnel
    @State private var password: String = ""
    @Environment(\.dismiss) private var dismiss
    let onSave: (SSHTunnel) -> Void
    
    init(tunnel: SSHTunnel, onSave: @escaping (SSHTunnel) -> Void) {
        _tunnel = State(initialValue: tunnel)
        self.onSave = onSave
        // Load password from keychain if it exists
        _password = State(initialValue: KeychainHelper.shared.get(forKey: tunnel.passwordKeychainKey) ?? "")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(tunnel.name.isEmpty ? "New Connection" : "Edit Connection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section {
                    TextField("Connection Name", text: $tunnel.name)
                    TextField("SSH Server Address", text: $tunnel.sshServer)
                    TextField("Port", value: $tunnel.port, format: .number.grouping(.never))
                    TextField("SSH Username", text: $tunnel.username)
                    
                    if !tunnel.useIdentityFile {
                        SecureField("Password", text: $password)
                    }
                }
                
                Section {
                    TextField("Local Bind Address", text: $tunnel.localBindAddress)
                    TextField("Local Port", value: $tunnel.localPort, format: .number.grouping(.never))
                }
                
                Section {
                    Toggle("Automatically configure SOCKS proxy", isOn: $tunnel.autoConfigureProxy)
                    Toggle("Strict Host Key Checking", isOn: $tunnel.strictHostKeyChecking)
                    
                    Toggle("Use SSH identity file", isOn: $tunnel.useIdentityFile)
                    
                    if tunnel.useIdentityFile {
                        HStack {
                            TextField("Identity File Path", text: $tunnel.identityFilePath)
                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.message = "Select SSH identity file"
                                
                                if panel.runModal() == .OK, let url = panel.url {
                                    tunnel.identityFilePath = url.path
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Advanced")) {
                    HStack {
                        Text("Send server alive messages every")
                        TextField("", value: $tunnel.serverAliveInterval, format: .number.grouping(.never))
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    // Save password to keychain if provided
                    if !password.isEmpty {
                        _ = KeychainHelper.shared.save(password, forKey: tunnel.passwordKeychainKey)
                    }
                    onSave(tunnel)
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tunnel.name.isEmpty || tunnel.sshServer.isEmpty || tunnel.username.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func closeWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
}
