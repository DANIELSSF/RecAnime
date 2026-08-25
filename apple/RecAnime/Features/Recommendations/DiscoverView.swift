import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Discover tab: genre chips + sort over a poster grid. Unfiltered lists come from `/v1/top`
/// (cached, and the only Jikan list that keeps working when MAL throttles search); a genre
/// switches to the filter-only search. Community recommendation pairs live one push away.
struct DiscoverView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case topRated, popular, airing
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .topRated: "Mejor valorados"
            case .popular: "Populares"
            case .airing: "En emisión"
            }
        }

        var systemImage: String {
            switch self {
            case .topRated: "star"
            case .popular: "flame"
            case .airing: "dot.radiowaves.left.and.right"
            }
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let api: any RecAnimeAPI
    @State private var genre: Genre?
    @State private var sort: Sort = .topRated
    @State private var loader: PagedLoader<AnimeSummary>
    @State private var showsSettings = false

    init(api: any RecAnimeAPI) {
        self.api = api
        _loader = State(initialValue: PagedLoader { page in try await Self.fetch(api, genre: nil, sort: .topRated, page: page) })
    }

    var body: some View {
        AnimeGrid(loader: loader) {
            communityLink
        } onSelect: { anime in
            router.open(anime, source: "grid-\(anime.malId)", remembering: deps.summaries)
        }
        .safeAreaBar(edge: .top) { chips }
        .navigationTitle("Descubrir")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle("\(sort.title) · \(genre?.localizedName ?? "Todos los géneros")")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { sortMenu }
            ToolbarItem(placement: .topBarTrailing) { AvatarButton { showsSettings = true } }.sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
        .onChange(of: genre) { _, _ in reload() }
        .onChange(of: sort) { _, _ in reload() }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar por", selection: $sort) {
                ForEach(Sort.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label(sort.title, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("discover.sort")
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    FilterChip(title: "Todos", isSelected: genre == nil) { withAnimation(.snappy) { genre = nil } }
                        .accessibilityIdentifier("discover.genre.all")
                    ForEach(Genre.featured) { item in
                        FilterChip(title: item.localizedName, isSelected: item == genre) { withAnimation(.snappy) { genre = item } }
                            .accessibilityIdentifier("discover.genre.\(item.id)")
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Entry point to the live MAL "if you liked → you'll like" feed.
    private var communityLink: some View {
        NavigationLink {
            CommunityRecommendationsView(api: api)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.thumb + 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recomendaciones de la comunidad").font(.subheadline.weight(.semibold))
                    Text("Pares «si te gustó, te gustará» de MyAnimeList, en vivo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.m)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover.community")
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
    }

    private func reload() {
        let api = api, genre = genre, sort = sort
        Task { await loader.replace { page in try await Self.fetch(api, genre: genre, sort: sort, page: page) } }
    }

    private static func fetch(_ api: any RecAnimeAPI, genre: Genre?, sort: Sort, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        guard let genre else {
            switch sort {
            case .topRated: return try await api.top(filter: nil, type: nil, page: page)
            case .popular: return try await api.top(filter: "bypopularity", type: nil, page: page)
            case .airing: return try await api.top(filter: "airing", type: nil, page: page)
            }
        }
        var query = BrowseQuery(genres: [genre.id])
        switch sort {
        case .topRated: query.orderBy = "score"
        case .popular: query.orderBy = "members"
        case .airing:
            query.orderBy = "members"
            query.status = "airing"
        }
        return try await api.browse(query, page: page)
    }
}
