import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Ranked list with glass filter chips.
struct TopView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case score = "", airing, upcoming, bypopularity, favorite
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .score: "Puntuación"
            case .airing: "Emisión"
            case .upcoming: "Próximos"
            case .bypopularity: "Populares"
            case .favorite: "Favoritos"
            }
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let api: any RecAnimeAPI
    @State private var filter: Filter = .score
    @State private var loader: PagedLoader<AnimeSummary>
    @State private var showsSettings = false

    init(api: any RecAnimeAPI) {
        self.api = api
        _loader = State(initialValue: PagedLoader { page in try await api.top(filter: nil, type: nil, page: page) })
    }

    var body: some View {
        List {
            ForEach(Array(loader.items.enumerated()), id: \.element.id) { index, anime in
                Button { router.open(anime, source: "top-\(anime.malId)", remembering: deps.summaries) } label: {
                    RankedAnimeRow(rank: index + 1, anime: anime)
                }
                .buttonStyle(.plain)
                .zoomSource("top-\(anime.malId)", cornerRadius: Theme.Radius.thumb)
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.Spacing.l, bottom: 10, trailing: Theme.Spacing.l))
                .task { await loader.loadMoreIfNeeded(currentItem: anime) }
            }
            if loader.state == .loadingMore || (loader.state == .loading && !loader.items.isEmpty) {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if loader.items.isEmpty {
                switch loader.state {
                case .loading: ProgressView()
                case let .failed(error):
                    EmptyStateView(
                        title: "No se pudo cargar",
                        message: LocalizedStringKey(error.userMessage),
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "Reintentar"
                    ) { Task { await loader.loadFirst() } }
                default: EmptyView()
                }
            }
        }
        .safeAreaBar(edge: .top) { chips }
        .navigationTitle("Top")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AvatarButton { showsSettings = true } } }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable { await loader.loadFirst() }
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
        .onChange(of: filter) { _, newValue in
            let api = api
            let value = newValue.rawValue.isEmpty ? nil : newValue.rawValue
            Task { await loader.replace { page in try await api.top(filter: value, type: nil, page: page) } }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(Filter.allCases) { item in
                        FilterChip(title: item.title, isSelected: item == filter) { withAnimation(.snappy) { filter = item } }
                            .accessibilityIdentifier("top.filter.\(item.rawValue.isEmpty ? "score" : item.rawValue)")
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Glass chip; the selected one becomes prominent (accent).
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected {
                Button(title, action: action).buttonStyle(.glassProminent).tint(Theme.accent)
            } else {
                Button(title, action: action).buttonStyle(.glass)
            }
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Rank · poster · title · meta · score.
struct RankedAnimeRow: View {
    let rank: Int?
    let anime: AnimeSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let rank {
                Text("\(rank)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 30)
            }
            PosterImage(url: anime.imageURL, width: 56, height: 84, cornerRadius: Theme.Radius.thumb)
            VStack(alignment: .leading, spacing: 4) {
                Text(anime.title).font(.headline).lineLimit(2)
                MetadataRow([anime.type, anime.episodes.map { "\($0) ep" }, anime.year.map(String.init)])
                HStack(spacing: Theme.Spacing.s) {
                    ScoreLabel(score: anime.score)
                    if let overlay = anime.library {
                        StatusBadge(LocalizedStringKey(overlay.status.spanish), color: Theme.status(overlay.status.rawValue))
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
