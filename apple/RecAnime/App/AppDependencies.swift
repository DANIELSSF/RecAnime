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
    let summaries = SummaryCache()
    /// Episode updates made offline (notification action) — replayed by `refreshLibrary`.
    let outbox = EpisodeOutbox(key: "ra.phone.outbox")
    let connectivity = ConnectivityMonitor()

    /// Keys of the on-disk snapshots that make a cold start render something without network.
    enum SnapshotKey {
        static let library = "library"
        static let seasonNow = "season.now"
        static let seasonUpcoming = "season.upcoming"
    }

    /// Season carousels age out after three days: a stale poster row is fine, a stale season is not.
    static let seasonSnapshotMaxAge: TimeInterval = 3 * 24 * 3600

    /// A library reload younger than this is redundant on a plain foreground return.
    private static let libraryFreshness: TimeInterval = 5 * 60

    /// Recent searches live in `UserDefaults` (SearchView reads them through `@AppStorage`).
    static let recentSearchesKey = "ra.recentSearches"

    var isDevBypass: Bool {
        session == nil
    }

    // MARK: Offline snapshots

    /// Paints the last known library before the first request; a no-op once the store has data.
    func hydrateFromSnapshots() async {
        guard !isResettingSnapshots, library.items.isEmpty else { return }
        guard let groups = await snapshots.load(LibraryGroups.self, key: SnapshotKey.library) else { return }
        library.applySnapshot(groups.all)
    }

    /// The single entry point for "bring the library up to date": drains the offline outbox first
    /// (so a queued +1 is not overwritten by the server's older value), reloads unless the last
    /// successful load is still fresh, and mirrors the result to disk for the next cold start.
    func refreshLibrary(force: Bool) async {
        if !outbox.isEmpty {
            await outbox.replay(api: api)
        }
        if !force, let last = library.lastLoadedAt, Date.now.timeIntervalSince(last) < Self.libraryFreshness {
            return
        }
        await library.load()
        guard library.lastError == nil else { return }
        await snapshots.save(library.groups, key: SnapshotKey.library)
    }

    /// Sign-out: everything derived from the account leaves memory and disk.
    /// True while a sign-out is wiping the disk snapshots: the next session must not hydrate from them.
    private var isResettingSnapshots = false

    func resetLocalData() async {
        library.clear()
        summaries.clear()
        outbox.clear()
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
        isResettingSnapshots = true
        await snapshots.clear()
        isResettingSnapshots = false
    }

    init(config: AppConfig = AppConfig.load(apiBaseURLOverride: AppDependencies.debugAPIOverride)) {
        self.config = config
        let tokenProvider: any TokenProvider
        // The API client is the single choke point for lost access: it reports a dead session or a
        // rejected account and the store turns that into a local sign-out with a reason on screen.
        let onAccessRevoked: AccessRevokedHandler?
        if config.hasAuthConfiguration, let supabaseURL = config.supabaseURL {
            let store = SessionStore(auth: SupabaseAuthFactory.makeClient(url: supabaseURL, publishableKey: config.supabasePublishableKey))
            session = store
            tokenProvider = store.tokenProvider
            onAccessRevoked = { reason in
                await store.revoke(reason)
                if reason == .emailNotAllowed {
                    // Forget the Google account so the next attempt shows the chooser.
                    await MainActor.run { GoogleSignInCoordinator.signOut() }
                }
            }
        } else {
            session = nil
            tokenProvider = DevTokenProvider()
            onAccessRevoked = nil
        }
        let client = APIClient(baseURL: config.apiBaseURL, tokenProvider: tokenProvider, onAccessRevoked: onAccessRevoked)
        api = LiveRecAnimeAPI(client: client)
        library = LibraryStore(api: api)
        schedule = ScheduleStore(api: api)
        notifications = NotificationCoordinator(schedule: schedule)
        watchSync = PhoneWatchSync(config: config, library: library, schedule: schedule, notifications: notifications)
    }

    static let apiOverrideKey = "ra.apiBaseURLOverride"

    /// The Settings override only exists in Debug; a Release sideload installed over a Debug build
    /// shares its UserDefaults and must never inherit a LAN URL from it.
    private static var debugAPIOverride: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: apiOverrideKey)
        #else
            nil
        #endif
    }
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
