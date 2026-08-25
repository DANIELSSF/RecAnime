import Foundation
import RecAnimeCore
import UserNotifications

/// Subset of UNUserNotificationCenter used by the scheduler (mockable in tests).
protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
    func removeAllPending()
}

extension UNUserNotificationCenter: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPending() {
        removeAllPendingNotificationRequests()
    }
}

/// Applies a plan to the notification center: removes stale requests, adds missing ones.
/// Identifiers are deterministic (`ep.<malId>.<episode>`) so applying the same plan twice is a no-op.
@MainActor
final class LocalNotificationScheduler {
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Asks for permission when undecided; returns whether notifications are allowed.
    func ensurePermission() async -> Bool {
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await (try? center.requestAuthorization()) ?? false
        default:
            return false
        }
    }

    func isAuthorized() async -> Bool {
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Diffs the desired plan against pending requests. Returns (added, removed) counts.
    @discardableResult
    func apply(_ plan: [PlannedNotification]) async -> (added: Int, removed: Int) {
        let pending = await Set(center.pendingIdentifiers().filter { $0.hasPrefix(NotificationPlanner.idPrefix) })
        let desired = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0) })
        let toRemove = pending.subtracting(desired.keys)
        if !toRemove.isEmpty {
            center.removePending(identifiers: Array(toRemove))
        }
        var added = 0
        for (id, item) in desired where !pending.contains(id) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = "anime.\(item.malID)"
            content.categoryIdentifier = Identifiers.episodeAiredCategory
            content.targetContentIdentifier = Identifiers.animeURL(malID: item.malID).absoluteString
            var info: [String: Any] = ["malId": item.malID, "fireDate": item.fireDate.timeIntervalSince1970]
            if let episode = item.episode {
                info["episode"] = episode
            }
            content.userInfo = info
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            added += 1
        }
        return (added, toRemove.count)
    }

    func cancelAll() {
        center.removeAllPending()
    }

    func pendingCount() async -> Int {
        await center.pendingIdentifiers().filter { $0.hasPrefix(NotificationPlanner.idPrefix) }.count
    }
}
