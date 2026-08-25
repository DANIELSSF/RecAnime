import BackgroundTasks
import Foundation
import RecAnimeCore

/// Periodic background refresh: re-plans notifications and pushes a snapshot to the Watch.
enum BackgroundRefresh {
    /// Must run before `application(_:didFinishLaunchingWithOptions:)` returns.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Identifiers.backgroundRefreshTask, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                let deps = AppDependencies.shared
                await deps.notifications.replan(requestPermission: false)
                await deps.watchSync.pushSnapshot()
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = { work.cancel() }
            schedule()
        }
    }

    /// Asks for a wake-up in ~6 hours; the system decides the actual time.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Identifiers.backgroundRefreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler.Error.unavailable on the simulator; nothing to do.
        }
    }
}
