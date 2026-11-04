import SwiftUI
import AVKit

@main
struct HubPlayerApp: App {
    @StateObject private var playerManager = PlayerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerManager)
                .fullScreenCover(isPresented: $playerManager.isPresenting) {
                    PlayerView()
                        .environmentObject(playerManager)
                }
        }
    }
}
