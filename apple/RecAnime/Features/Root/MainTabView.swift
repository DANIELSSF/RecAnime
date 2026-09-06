import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Tab shell: system tab bar, search tab and bottom accessory all render in Liquid Glass.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Namespace private var seasonZoom
    @Namespace private var topZoom
    @Namespace private var recommendationsZoom
    @Namespace private var libraryZoom
    @Namespace private var searchZoom
    /// Library failures are transient: the toast says what happened and offers one retry.
    @State private var libraryError: String?
    @State private var errorDismissal: Task<Void, Never>?
    @State private var showsDevBanner = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Inicio", systemImage: "house", value: AppTab.season) {
                stack(for: .season, namespace: seasonZoom) { SeasonView(api: deps.api) }
            }
            Tab("Top", systemImage: "trophy", value: AppTab.top) {
                stack(for: .top, namespace: topZoom) { TopView(api: deps.api) }
            }
            Tab("Descubrir", systemImage: "safari", value: AppTab.recommendations) {
                stack(for: .recommendations, namespace: recommendationsZoom) { DiscoverView(api: deps.api) }
            }
            Tab("Mi lista", systemImage: "bookmark", value: AppTab.library) {
                stack(for: .library, namespace: libraryZoom) { MyListView() }
            }
            Tab(value: AppTab.search, role: .search) {
                stack(for: .search, namespace: searchZoom) { SearchView(api: deps.api) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: library.nowWatching != nil) {
            if let item = library.nowWatching {
                NowWatchingBar(item: item)
            }
        }
        .safeAreaInset(edge: .top) { banners }
        .overlay(alignment: .bottom) { errorToast.animation(.snappy, value: libraryError) }
        .task {
            await deps.hydrateFromSnapshots()
            await deps.refreshLibrary(force: true)
        }
        .task { await announceDevelopmentMode() }
        .onChange(of: library.lastError) { _, error in showError(error) }
        .onDisappear { errorDismissal?.cancel() }
    }

    /// Top banners: offline first, then the developer-mode hint (Debug builds without Supabase).
    /// With nothing to show the stack is zero-height, so the inset never shifts the tabs.
    private var banners: some View {
        VStack(spacing: Theme.Spacing.s) {
            if !deps.connectivity.isOnline {
                ToastView(message: "Sin conexión")
            }
            if showsDevBanner {
                ToastView(message: "Modo desarrollo")
            }
        }
        .padding(.top, hasBanner ? Theme.Spacing.xs : 0)
        .animation(.snappy, value: deps.connectivity.isOnline)
        .animation(.snappy, value: showsDevBanner)
    }

    private var hasBanner: Bool {
        !deps.connectivity.isOnline || showsDevBanner
    }

    /// Sits above the tab bar so it never covers the bottom accessory's controls.
    @ViewBuilder private var errorToast: some View {
        if let libraryError {
            ToastView(message: libraryError, actionTitle: "Reintentar") {
                Task { await deps.refreshLibrary(force: true) }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showError(_ error: APIError?) {
        errorDismissal?.cancel()
        guard let error else {
            libraryError = nil
            return
        }
        libraryError = error.userMessage
        errorDismissal = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            libraryError = nil
        }
    }

    private func announceDevelopmentMode() async {
        #if DEBUG
            guard deps.isDevBypass else { return }
            showsDevBanner = true
            try? await Task.sleep(for: .seconds(3))
            showsDevBanner = false
        #endif
    }

    /// One NavigationStack per tab sharing a zoom namespace with its destinations.
    private func stack(for tab: AppTab, namespace: Namespace.ID, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: router.path(for: tab)) {
            root().navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .environment(\.zoomNamespace, namespace)
    }
}

/// Maps routes to screens (shared by every tab's NavigationStack).
struct RouteView: View {
    @Environment(AppDependencies.self) private var deps
    let route: Route

    var body: some View {
        switch route {
        case let .anime(id, source):
            AnimeDetailView(malID: id, api: deps.api)
                .zoomDestination(sourceID: source)
        case let .seasonGrid(kind):
            SeasonGridView(kind: kind, api: deps.api)
        case .seasonBrowser:
            SeasonBrowserView(api: deps.api)
        case let .franchise(id):
            FranchiseListView(malID: id, api: deps.api)
        case .calendar:
            WeeklyScheduleView(api: deps.api)
        }
    }
}
