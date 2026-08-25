import UIKit
import UserNotifications

/// UIKit entry points that SwiftUI does not expose: background task registration and the
/// notification center delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefresh.register()
        NotificationDelegate.registerCategories()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundRefresh.schedule()
    }
}
