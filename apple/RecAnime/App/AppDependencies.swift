import Foundation
import Observation
import RecAnimeCore
import RecAnimeKit

/// Composition root: configuration, auth session and the shared stores.
@MainActor
@Observable
final class AppDependencies {
    /// Single instance shared with UIKit entry points (app delegate, background tasks, notifications).
    static let shared = AppDependencies()

    let config: AppConfig
    /// nil when Supabase is not configured (Secrets.xcconfig missing) — debug builds then use the dev bypass.
    let session: SessionStore?
    let api: any RecAnimeAPI
    let library: LibraryStore
    let schedule: ScheduleStore
    let notifications: NotificationCoordinator
    let watchSync: PhoneWatchSync
    let snapshots = SnapshotCache()
    let router = Router()

    var isDevBypass: Bool {
        session == nil
    }

    init(config: AppConfig = AppConfig.load(apiBaseURLOverride: UserDefaults.standard.string(forKey: AppDependencies.apiOverrideKey))) {
        self.config = config
        let tokenProvider: any TokenProvider
        if config.hasAuthConfiguration, let supabaseURL = config.supabaseURL {
            let store = SessionStore(auth: SupabaseAuthFactory.makeClient(url: supabaseURL, publishableKey: config.supabasePublishableKey))
            session = store
            tokenProvider = store.tokenProvider
        } else {
            session = nil
            tokenProvider = DevTokenProvider()
        }
        let client = APIClient(baseURL: config.apiBaseURL, tokenProvider: tokenProvider)
        api = LiveRecAnimeAPI(client: client)
        library = LibraryStore(api: api)
        schedule = ScheduleStore(api: api)
        notifications = NotificationCoordinator(schedule: schedule)
        watchSync = PhoneWatchSync(config: config, library: library, schedule: schedule, notifications: notifications)
    }

    static let apiOverrideKey = "ra.apiBaseURLOverride"
}

/// Debug-only token provider for the API's DEV_BYPASS_AUTH mode (the server ignores the token).
struct DevTokenProvider: TokenProvider {
    func accessToken() async throws -> String {
        "dev-bypass"
    }

    func forceRefresh() async throws -> String {
        "dev-bypass"
    }
}
