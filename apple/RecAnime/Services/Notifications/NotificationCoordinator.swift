import Foundation
import Observation
import RecAnimeCore
import RecAnimeKit
import UserNotifications

/// Keeps local notifications in sync with the airing schedule: refresh → plan → apply.
@MainActor
@Observable
final class NotificationCoordinator {
    static let enabledKey = "ra.notifications.enabled"
    static let offsetKey = "ra.notifications.offset"

    private(set) var lastPlannedAt: Date?
    private(set) var pendingCount = 0
    private(set) var nextFire: PlannedNotification?
    private(set) var authorized = false

    private let schedule: ScheduleStore
    private let scheduler: LocalNotificationScheduler
    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?

    init(schedule: ScheduleStore, scheduler: LocalNotificationScheduler = LocalNotificationScheduler(), defaults: UserDefaults = .standard) {
        self.schedule = schedule
        self.scheduler = scheduler
        self.defaults = defaults
    }

    var settings: NotificationSettings {
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let minutes = defaults.integer(forKey: Self.offsetKey)
        return NotificationSettings(enabled: enabled, offsetSeconds: TimeInterval(minutes * 60))
    }

    /// Re-plans when the last plan is older than `maxAge` (foreground return).
    func replanIfStale(maxAge: TimeInterval = 15 * 60) async {
        if let lastPlannedAt, Date.now.timeIntervalSince(lastPlannedAt) < maxAge {
            return
        }
        await replan()
    }

    /// Debounced re-plan after library edits (several taps → one refresh).
    func scheduleReplan(after delay: Duration = .seconds(2)) {
        // A plan finished moments ago (e.g. the launch cycle) already reflects this change.
        if let lastPlannedAt, Date.now.timeIntervalSince(lastPlannedAt) < 10 {
            return
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.replan()
        }
    }

    /// Full cycle. `requestPermission` triggers the system prompt when undecided.
    func replan(requestPermission: Bool = true) async {
        let settings = settings
        guard settings.enabled else {
            scheduler.cancelAll()
            pendingCount = 0
            nextFire = nil
            lastPlannedAt = .now
            return
        }
        await schedule.refresh()
        let plan = NotificationPlanner.plan(schedule: schedule.items, now: .now, settings: settings)
        authorized = requestPermission && !plan.isEmpty ? await scheduler.ensurePermission() : await scheduler.isAuthorized()
        guard authorized else {
            pendingCount = 0
            nextFire = plan.first
            lastPlannedAt = .now
            return
        }
        await scheduler.apply(plan)
        pendingCount = await scheduler.pendingCount()
        nextFire = plan.first
        lastPlannedAt = .now
    }

    func cancelAll() {
        scheduler.cancelAll()
        pendingCount = 0
        nextFire = nil
    }
}
