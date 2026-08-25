import RecAnimeCore
import RecAnimeUI
import SwiftUI

@main
struct RecAnimeApp: App {
    private let config = AppConfig.load()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appConfig, config)
                .tint(Theme.accent)
        }
    }
}

extension EnvironmentValues {
    /// Build configuration (API base URL, Supabase endpoint) resolved at launch.
    @Entry var appConfig: AppConfig = AppConfig.load()
}
