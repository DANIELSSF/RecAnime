import WatchKit

/// Background refresh entry point for the Watch app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchDependencies.shared.connectivity.activate()
            // First wake-up of the install: without it nothing schedules one until a manual refresh.
            WatchDependencies.scheduleBackgroundRefresh()
        }
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
