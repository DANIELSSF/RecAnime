import RecAnimeCore
import RecAnimeUI
import SwiftUI

@main
struct RecAnimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var deps = AppDependencies.shared

    init() {
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(deps)
                .environment(deps.router)
                .environment(deps.library)
                .environment(deps.schedule)
                .environment(deps.notifications)
                .environment(deps.watchSync)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    deps.watchSync.activate()
                    Task { await deps.notifications.replanIfStale() }
                }
                .onChange(of: deps.library.version) { _, _ in
                    deps.notifications.scheduleReplan()
                    Task { await deps.watchSync.pushSnapshot() }
                }
                .onOpenURL { url in
                    if !GoogleSignInCoordinator.handle(url) {
                        deps.router.handle(url)
                    }
                }
                .task {
                    #if DEBUG
                        // `xcrun simctl launch <udid> com.danielsantiago.recanime -ra-open recanime://anime/52991`
                        let args = ProcessInfo.processInfo.arguments
                        if let index = args.firstIndex(of: "-ra-open"), index + 1 < args.count, let url = URL(string: args[index + 1]) {
                            try? await Task.sleep(for: .milliseconds(300))
                            deps.router.handle(url)
                        }
                    #endif
                }
        }
    }
}
