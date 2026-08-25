import Foundation
import RecAnimeCore
import RecAnimeKit
import UserNotifications

/// Registers the notification category and handles taps/actions (also mirrored from the Watch).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let markWatchedAction = "MARK_WATCHED"
    static let openAction = "OPEN"

    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let markWatched = UNNotificationAction(identifier: markWatchedAction, title: "Marcar visto", options: [.authenticationRequired])
        let open = UNNotificationAction(identifier: openAction, title: "Ver detalles", options: [.foreground])
        let category = UNNotificationCategory(identifier: Identifiers.episodeAiredCategory, actions: [markWatched, open], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let malID = info["malId"] as? Int else { return }
        let episode = info["episode"] as? Int
        let action = response.actionIdentifier
        await MainActor.run {
            let deps = AppDependencies.shared
            switch action {
            case NotificationDelegate.markWatchedAction:
                guard let episode else { return }
                Task {
                    _ = try? await deps.api.adjustEpisodes(malID, .set(episode))
                    await deps.library.load()
                }
            default:
                deps.router.open(anime: malID, in: .library)
            }
        }
    }
}
