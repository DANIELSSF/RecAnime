import Foundation
import Observation
import RecAnimeCore
import RecAnimeKit
import WatchKit
import WidgetKit

/// Composition root of the Watch app.
@MainActor
@Observable
final class WatchDependencies {
    static let shared = WatchDependencies()
    private static let devBypassKey = "ra.watch.devBypass"

    let config: AppConfig
    let session: SessionStore?
    let api: any RecAnimeAPI
    let library: LibraryStore
    let schedule: ScheduleStore
    let outbox = Outbox()
    let appGroup = AppGroupStore()
    private(set) var connectivity: WatchConnectivityReceiver!
    /// Set from the iPhone's context when the API runs with DEV_BYPASS_AUTH (no Supabase configured).
    private(set) var devBypass: Bool
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        devBypass = UserDefaults.standard.bool(forKey: Self.devBypassKey)
        let tokenProvider: any TokenProvider
        if config.hasAuthConfiguration, let url = config.supabaseURL {
            let store = SessionStore(auth: SupabaseAuthFactory.makeClient(url: url, publishableKey: config.supabasePublishableKey))
            session = store
            tokenProvider = store.tokenProvider
        } else {
            session = nil
            tokenProvider = WatchDevTokenProvider()
        }
        api = LiveRecAnimeAPI(client: APIClient(baseURL: config.apiBaseURL, tokenProvider: tokenProvider))
        library = LibraryStore(api: api, debounce: .zero)
        schedule = ScheduleStore(api: api)
        connectivity = WatchConnectivityReceiver(deps: self)
        session?.bootstrap()
        if let snapshot = appGroup.read(WatchSnapshot.self, file: AppGroupStore.snapshotFile) {
            library.applySnapshot(snapshot.watching)
            schedule.replace(with: snapshot.schedule, generatedAt: snapshot.generatedAt)
        }
    }

    /// Whether the app can call the API (a session exists, or the API does not require one).
    var canUseAPI: Bool {
        if session == nil {
            return true
        } // no Supabase configured at build time → dev bypass build
        if case .signedIn = session?.state {
            return true
        }
        return false
    }

    func setDevBypass(_ value: Bool) {
        devBypass = value
        UserDefaults.standard.set(value, forKey: Self.devBypassKey)
    }

    /// Pulls fresh data, replays queued episode changes and refreshes the complication.
    func refresh(throttle: Bool) async {
        guard canUseAPI else { return }
        if throttle, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 120 {
            return
        }
        await outbox.replay(api: api)
        await library.load()
        await schedule.refresh()
        if let error = library.lastError ?? schedule.lastError {
            lastError = error.userMessage
        } else {
            lastError = nil
            lastRefresh = .now
            persistSnapshot()
        }
        Self.scheduleBackgroundRefresh()
    }

    /// Records an episode as watched: local first, then the API (queued when offline).
    func markEpisode(_ item: RecAnimeCore.LibraryItem, delta: Int) async {
        let target = max(item.entry.episodesWatched + delta, 0)
        library.increment(for: item.anime, by: delta)
        await library.flush()
        if let error = library.lastError, case .network = error {
            outbox.enqueue(malID: item.anime.malId, target: target)
            lastError = "Sin conexión: se enviará más tarde."
        } else {
            lastError = nil
            connectivity.notifyLibraryChanged(malID: item.anime.malId, episodes: target)
        }
        persistSnapshot()
        WKInterfaceDevice.current().play(.click)
    }

    /// Applies data pushed by the iPhone.
    func apply(snapshot: WatchSnapshot) {
        library.applySnapshot(snapshot.watching)
        schedule.replace(with: snapshot.schedule, generatedAt: snapshot.generatedAt)
        persistSnapshot()
    }

    func signOutLocally() async {
        await session?.signOut(scope: .local)
        library.applySnapshot([])
        schedule.replace(with: [], generatedAt: .now)
        persistSnapshot()
    }

    private func persistSnapshot() {
        let snapshot = WatchSnapshot(watching: library.groups.watching, schedule: schedule.items, generatedAt: .now)
        try? appGroup.write(snapshot, file: AppGroupStore.snapshotFile)
        ComplicationSnapshotWriter.write(schedule: schedule.items, store: appGroup)
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date(timeIntervalSinceNow: 3600), userInfo: nil) { _ in }
    }
}

struct WatchDevTokenProvider: TokenProvider {
    func accessToken() async throws -> String {
        "dev-bypass"
    }

    func forceRefresh() async throws -> String {
        "dev-bypass"
    }
}
