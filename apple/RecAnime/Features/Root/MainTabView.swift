import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Tab shell: system tab bar, search tab and bottom accessory all render in Liquid Glass.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Temporada", systemImage: "calendar", value: AppTab.season) {
                NavigationStack(path: router.path(for: .season)) {
                    SeasonView(api: deps.api).navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("Top", systemImage: "trophy", value: AppTab.top) {
                NavigationStack(path: router.path(for: .top)) {
                    TopView(api: deps.api).navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("Recomendados", systemImage: "sparkles", value: AppTab.recommendations) {
                NavigationStack(path: router.path(for: .recommendations)) {
                    RecommendationsView(api: deps.api).navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("Mi lista", systemImage: "bookmark", value: AppTab.library) {
                NavigationStack(path: router.path(for: .library)) {
                    MyListView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: router.path(for: .search)) {
                    SearchView(api: deps.api).navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
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
}

/// Maps routes to screens (shared by every tab's NavigationStack).
struct RouteView: View {
    @Environment(AppDependencies.self) private var deps
    let route: Route

    var body: some View {
        switch route {
        case let .anime(id):
            AnimeDetailView(malID: id, api: deps.api)
        case let .seasonGrid(kind):
            SeasonGridView(kind: kind, api: deps.api)
        case .seasonBrowser:
            SeasonBrowserView(api: deps.api)
        case let .franchise(id):
            FranchiseListView(malID: id, api: deps.api)
        }
    }
}
