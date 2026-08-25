import RecAnimeCore
import RecAnimeUI
import SwiftUI

@main
struct RecAnimeApp: App {
    @State private var deps = AppDependencies()

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
                .tint(Theme.accent)
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
