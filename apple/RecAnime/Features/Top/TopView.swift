import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Ranked list with glass filter chips and a type menu.
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

    enum Kind: String, CaseIterable, Identifiable {
        case all = "", tv, movie, ova, ona, special
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all: "Todos los tipos"
            case .tv: "TV"
            case .movie: "Películas"
            case .ova: "OVA"
            case .ona: "ONA"
            case .special: "Especiales"
            }
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let api: any RecAnimeAPI
    @State private var filter: Filter = .score
    @State private var kind: Kind = .all
    @State private var loader: PagedLoader<AnimeSummary>
    @State private var showsSettings = false

    init(api: any RecAnimeAPI) {
        self.api = api
        _loader = State(initialValue: PagedLoader { page in try await api.top(filter: nil, type: nil, page: page) })
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loader.items.isEmpty {
                    switch loader.state {
                    case .loading: ProgressView().padding(.top, 80)
                    case let .failed(error):
                        EmptyStateView(
                            title: "No se pudo cargar",
                            message: LocalizedStringKey(error.userMessage),
                            systemImage: "wifi.exclamationmark",
                            actionTitle: "Reintentar"
                        ) { Task { await loader.loadFirst() } }
                            .padding(.top, 80)
                    default: EmptyView()
                    }
                }
                ForEach(Array(loader.items.enumerated()), id: \.element.id) { index, anime in
                    Button { router.open(anime, source: "top-\(anime.malId)", remembering: deps.summaries) } label: {
                        RankedAnimeRow(rank: index + 1, anime: anime)
                            .padding(.vertical, 10)
                            .padding(.horizontal, Theme.Spacing.l)
                    }
                    .buttonStyle(.plain)
                    .zoomSource("top-\(anime.malId)", cornerRadius: Theme.Radius.thumb)
                    .task { await loader.loadMoreIfNeeded(currentItem: anime) }
                    Divider().padding(.leading, Theme.Spacing.l + 30 + Theme.Spacing.m)
                }
                if loader.state == .loadingMore || (loader.state == .loading && !loader.items.isEmpty) {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
        }
        .scrollDisabled(loader.items.isEmpty)
        .refreshable { await loader.loadFirst() }
        .safeAreaBar(edge: .top) { chips }
        .navigationTitle("Top")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(kind == .all ? "" : kind.title)
        .toolbar {
            // Keep a glass toolbar item here: when the avatar (shared background hidden) is the only
            // item, the glass chips in the safeAreaBar are laid out but rendered fully transparent.
            ToolbarItem(placement: .topBarLeading) { kindMenu }
            ToolbarItem(placement: .topBarTrailing) { AvatarButton { showsSettings = true } }.sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
        .onChange(of: filter) { _, _ in reload() }
        .onChange(of: kind) { _, _ in reload() }
    }

    private func reload() {
        let api = api
        let filter = filter.rawValue.isEmpty ? nil : filter.rawValue
        let type = kind.rawValue.isEmpty ? nil : kind.rawValue
        Task { await loader.replace { page in try await api.top(filter: filter, type: type, page: page) } }
    }

    private var kindMenu: some View {
        Menu {
            Picker("Tipo", selection: $kind) {
                ForEach(Kind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label("Tipo", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityIdentifier("top.type")
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
        .controlSize(.large)
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
