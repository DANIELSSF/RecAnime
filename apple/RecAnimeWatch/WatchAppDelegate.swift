import WatchKit

/// Background refresh entry point for the Watch app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchDependencies.shared.connectivity.activate() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let refresh = task as? WKApplicationRefreshBackgroundTask {
                Task { @MainActor in
                    await WatchDependencies.shared.refresh(throttle: false)
                    WatchDependencies.scheduleBackgroundRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
