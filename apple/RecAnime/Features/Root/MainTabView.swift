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

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Inicio", systemImage: "house", value: AppTab.season) {
                stack(for: .season, namespace: seasonZoom) { SeasonView(api: deps.api) }
            }
            Tab("Top", systemImage: "trophy", value: AppTab.top) {
                stack(for: .top, namespace: topZoom) { TopView(api: deps.api) }
            }
            Tab("Descubrir", systemImage: "sparkles", value: AppTab.recommendations) {
                stack(for: .recommendations, namespace: recommendationsZoom) { RecommendationsView(api: deps.api) }
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
        .task { await library.load() }
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
        }
    }
}
