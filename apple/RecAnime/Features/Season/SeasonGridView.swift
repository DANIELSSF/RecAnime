import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Three-column poster grid with infinite scroll for a season.
struct SeasonGridView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let kind: SeasonKind
    @State private var loader: PagedLoader<AnimeSummary>

    init(kind: SeasonKind, api: any RecAnimeAPI) {
        self.kind = kind
        _loader = State(initialValue: PagedLoader { page in
            switch kind {
            case .now: try await api.seasonNow(filter: nil, page: page)
            case .upcoming: try await api.seasonUpcoming(filter: nil, page: page)
            case let .specific(year, season): try await api.season(year: year, season: season, filter: nil, page: page)
            }
        })
    }

    var body: some View {
        AnimeGrid(loader: loader) { router.open($0, source: "grid-\($0.malId)", remembering: deps.summaries) }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.large)
            .task {
                if loader.items.isEmpty {
                    await loader.loadFirst()
                }
            }
    }
}

/// Adaptive grid backed by a PagedLoader, with an optional header above the posters.
struct AnimeGrid<Header: View>: View {
    let loader: PagedLoader<AnimeSummary>
    let onSelect: (AnimeSummary) -> Void
    @ViewBuilder let header: () -> Header
    @ScaledMetric(relativeTo: .subheadline) private var minWidth: CGFloat = 105

    init(loader: PagedLoader<AnimeSummary>, @ViewBuilder header: @escaping () -> Header, onSelect: @escaping (AnimeSummary) -> Void) {
        self.loader = loader
        self.header = header
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            header()
            if loader.items.isEmpty, case let .failed(error) = loader.state {
                EmptyStateView(
                    title: "No se pudo cargar",
                    message: LocalizedStringKey(error.userMessage),
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Reintentar"
                ) { Task { await loader.loadFirst() } }
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: Theme.Spacing.m, alignment: .top)], spacing: Theme.Spacing.l) {
                    ForEach(loader.items) { anime in
                        Button { onSelect(anime) } label: {
                            GridPoster(anime: anime)
                        }
                        .buttonStyle(.plain)
                        .zoomSource("grid-\(anime.malId)")
                        .task { await loader.loadMoreIfNeeded(currentItem: anime) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                if loader.state == .loadingMore || (loader.state == .loading && loader.items.isEmpty) {
                    ProgressView().padding()
                }
            }
        }
        .scrollDisabled(loader.items.isEmpty)
        .refreshable { await loader.loadFirst() }
    }
}

private struct GridPoster: View {
    let anime: AnimeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                PosterImage(url: anime.imageURL, width: proxy.size.width, height: proxy.size.width * 1.5)
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            Text(anime.title).font(.footnote.weight(.semibold)).lineLimit(2, reservesSpace: true)
            if let overlay = anime.library {
                StatusBadge(LocalizedStringKey(overlay.status.spanish), color: Theme.status(overlay.status.rawValue))
            } else {
                ScoreLabel(score: anime.score)
            }
        }
    }
}

extension AnimeGrid where Header == EmptyView {
    init(loader: PagedLoader<AnimeSummary>, onSelect: @escaping (AnimeSummary) -> Void) {
        self.init(loader: loader, header: { EmptyView() }, onSelect: onSelect)
    }
}

extension WatchStatus {
    var spanish: String {
        switch self {
        case .pending: "Pendiente"
        case .watching: "Viendo"
        case .watched: "Visto"
        case .unknown: "—"
        }
    }
}
