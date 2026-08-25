import RecAnimeCore
import RecAnimeUI
import SwiftUI

@main
struct RecAnimeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchingListView()
            }
            .tint(Theme.accent)
        }
    }
}
