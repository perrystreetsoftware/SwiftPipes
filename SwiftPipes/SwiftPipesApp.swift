import SwiftUI

@main
struct SwiftPipesApp: App {
    @StateObject private var tunnelManager = SSHTunnelManager()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(tunnelManager)
        } label: {
            Image(systemName: tunnelManager.hasActiveConnections ? "cloud.fill" : "cloud")
        }
    }
}
