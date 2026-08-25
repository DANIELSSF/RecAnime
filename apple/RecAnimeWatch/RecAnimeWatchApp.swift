import RecAnimeCore
import RecAnimeUI
import SwiftUI

@main
struct RecAnimeWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var deps = WatchDependencies.shared
    @State private var path: [Int] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                WatchRootView()
                    .navigationDestination(for: Int.self) { malID in
                        WatchAnimeDetailView(malID: malID)
                    }
            }
            .environment(deps)
            .environment(deps.library)
            .environment(deps.schedule)
            .tint(Theme.accent)
            .onOpenURL { url in
                if url.host == "anime", let id = Int(url.lastPathComponent) {
                    path = [id]
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    deps.connectivity.activate()
                    Task { await deps.refresh(throttle: true) }
                }
            }
        }
    }
}
