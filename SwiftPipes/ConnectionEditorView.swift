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
                    Picker("SOCKS proxy mode", selection: $tunnel.proxyMode) {
                        Text("Off").tag(ProxyMode.off)
                        Text("Route all traffic").tag(ProxyMode.all)
                        Text("Only selected domains / IPs").tag(ProxyMode.selective)
                    }
                    .pickerStyle(.menu)

                    if tunnel.proxyMode == .selective {
                        SelectiveHostsEditor(hosts: $tunnel.selectiveHosts)
                    }

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
                                panel.showsHiddenFiles = true
                                panel.treatsFilePackagesAsDirectories = true
                                panel.message = "Select SSH identity file"

                                // Default to the current identity file's directory if set,
                                // otherwise open ~/.ssh (creating that directory shortcut
                                // is not necessary — NSOpenPanel just falls back if missing).
                                let sshDir = (NSString(string: "~/.ssh").expandingTildeInPath as String)
                                if !tunnel.identityFilePath.isEmpty {
                                    let expanded = NSString(string: tunnel.identityFilePath).expandingTildeInPath
                                    panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
                                } else if FileManager.default.fileExists(atPath: sshDir) {
                                    panel.directoryURL = URL(fileURLWithPath: sshDir)
                                }

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
        .frame(width: 500, height: 680)
    }

    private func closeWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
}

private struct SelectiveHostsEditor: View {
    @Binding var hosts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Only these hosts go through the SOCKS proxy. Everything else goes DIRECT.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Examples: www.example.com · *.example.com · 10.0.0.5 · 192.168.1.0/24")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(hosts.indices, id: \.self) { idx in
                    HStack {
                        TextField("host, *.domain, IP, or CIDR", text: $hosts[idx])
                            .textFieldStyle(.roundedBorder)
                        Button {
                            hosts.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
            }

            Button {
                hosts.append("")
            } label: {
                Label("Add host", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
