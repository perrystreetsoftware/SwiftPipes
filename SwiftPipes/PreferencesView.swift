import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var preferences = PreferencesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Text("Preferences")
                .font(.title2)
                .fontWeight(.semibold)
                .padding()

            Form {
                Section(header: Text("General")) {
                    Toggle("Launch at Login", isOn: $preferences.launchAtLogin)
                        .help("Automatically start SwiftPipes when you log in")

                    Toggle("Show Notifications", isOn: $preferences.showNotifications)
                        .help("Show notifications when connections are established or disconnected")
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version:")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("© \(String(Calendar.current.component(.year, from: Date()))) Perry Street Software, Inc. Licensed under the MIT License.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 380)
    }

    private func closeWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
}
