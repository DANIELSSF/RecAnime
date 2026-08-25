import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Home: continue watching, this season, upcoming, browse by season.
struct SeasonView: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(AppDependencies.self) private var deps
    @State private var now: PagedLoader<AnimeSummary>
    @State private var upcoming: PagedLoader<AnimeSummary>
    @State private var showsSettings = false

    init(api: any RecAnimeAPI) {
        _now = State(initialValue: PagedLoader { page in try await api.seasonNow(filter: nil, page: page) })
        _upcoming = State(initialValue: PagedLoader { page in try await api.seasonUpcoming(filter: nil, page: page) })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !library.groups.watching.isEmpty {
                    continueWatching
                }
                section("Esta temporada", loader: now, kind: .now)
                section("Próximamente", loader: upcoming, kind: .upcoming)
                browseRow
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .navigationTitle("Inicio")
        .navigationSubtitle(currentSeasonLabel)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AvatarButton { showsSettings = true }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable {
            async let a: Void = now.loadFirst()
            async let b: Void = upcoming.loadFirst()
            async let c: Void = library.load()
            _ = await (a, b, c)
        }
        .task {
            if now.items.isEmpty {
                await now.loadFirst()
            }
            if upcoming.items.isEmpty {
                await upcoming.loadFirst()
            }
        }
    }

    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Sigue viendo")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(library.groups.watching.prefix(10)) { item in
                        Button { router.open(item.anime, source: "continue-\(item.anime.malId)", remembering: deps.summaries) } label: {
                            PosterCard(
                                title: item.anime.title,
                                subtitle: progressLabel(item),
                                imageURL: item.anime.imageURL,
                                progress: progressFraction(item)
                            )
                        }
                        .buttonStyle(.plain)
                        .zoomSource("continue-\(item.anime.malId)")
                        .accessibilityIdentifier("poster-continue-\(item.anime.malId)")
                        .contextMenu {
                            Button("Marcar episodio visto", systemImage: "plus") { library.increment(for: item.anime) }
                            Button("Marcar temporada vista", systemImage: "checkmark") {
                                Task { _ = try? await library.setStatus(.watched, for: item.anime) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .scrollTargetLayout()
                .animation(.snappy, value: library.version)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func section(_ title: LocalizedStringKey, loader: PagedLoader<AnimeSummary>, kind: SeasonKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title) {
                NavigationLink("Ver todo", value: Route.seasonGrid(kind))
            }
            switch loader.state {
            case .loading where loader.items.isEmpty:
                SkeletonCarousel()
            case let .failed(error) where loader.items.isEmpty:
                ErrorBanner(message: error.userMessage) { Task { await loader.loadFirst() } }
            default:
                PosterCarousel(items: loader.items, sourcePrefix: kind == .now ? "season-now" : "season-upcoming") { anime in
                    router.open(anime, source: "\(kind == .now ? "season-now" : "season-upcoming")-\(anime.malId)", remembering: deps.summaries)
                }
            }
        }
    }

    private var browseRow: some View {
        NavigationLink(value: Route.seasonBrowser) {
            HStack {
                Label("Explorar por temporada", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.l)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Spacing.l)
        }
        .buttonStyle(.plain)
    }

    private var currentSeasonLabel: String {
        let month = Calendar.current.component(.month, from: .now)
        let year = Calendar.current.component(.year, from: .now)
        let season = switch month {
        case 1 ... 3: "Invierno"
        case 4 ... 6: "Primavera"
        case 7 ... 9: "Verano"
        default: "Otoño"
        }
        return "\(season) \(year)"
    }

    private func progressLabel(_ item: RecAnimeCore.LibraryItem) -> String {
        if let total = item.progress.episodesTotal {
            return "ep \(item.entry.episodesWatched)/\(total)"
        }
        return "ep \(item.entry.episodesWatched)"
    }

    private func progressFraction(_ item: RecAnimeCore.LibraryItem) -> Double {
        guard let total = item.progress.episodesTotal, total > 0 else { return 0.6 }
        return min(Double(item.entry.episodesWatched) / Double(total), 1)
    }
}

/// Horizontal poster carousel shared by the home sections.
struct PosterCarousel: View {
    let items: [AnimeSummary]
    var sourcePrefix: String = "carousel"
    let onSelect: (AnimeSummary) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Large type: one poster per row so titles stay readable without horizontal scrolling.
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(items.prefix(8)) { anime in
                    Button { onSelect(anime) } label: {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            PosterImage(url: anime.imageURL, width: 80, height: 120)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(anime.title).font(.headline)
                                Text(subtitle(anime)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .zoomSource("\(sourcePrefix)-\(anime.malId)")
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else {
            carousel
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(items) { anime in
                    Button { onSelect(anime) } label: {
                        PosterCard(title: anime.title, subtitle: subtitle(anime), imageURL: anime.imageURL)
                    }
                    .buttonStyle(.plain)
                    .zoomSource("\(sourcePrefix)-\(anime.malId)")
                    .accessibilityIdentifier("poster-\(sourcePrefix)-\(anime.malId)")
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func subtitle(_ anime: AnimeSummary) -> String {
        [anime.type, anime.episodes.map { "\($0) ep" }].compactMap(\.self).joined(separator: " · ")
    }
}

/// Round avatar button that opens Settings.
struct AvatarButton: View {
    @Environment(AppDependencies.self) private var deps
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let url = deps.session?.user?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            } else {
                initials
            }
        }
        .accessibilityLabel("Ajustes")
    }

    private var initials: some View {
        Text(String((deps.session?.user?.name ?? deps.session?.user?.email ?? "Dev").prefix(1)).uppercased())
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.heroGradient, in: Circle())
    }
}
