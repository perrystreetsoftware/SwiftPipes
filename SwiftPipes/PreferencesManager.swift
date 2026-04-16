import Foundation
import ServiceManagement

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            configureLaunchAtLogin()
        }
    }
    
    @Published var showNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showNotifications, forKey: "showNotifications")
        }
    }
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.showNotifications = UserDefaults.standard.bool(forKey: "showNotifications")
    }
    
    private func configureLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                    print("Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("Launch at login disabled")
                }
            } catch {
                print("Failed to configure launch at login: \(error)")
            }
        }
    }
}
