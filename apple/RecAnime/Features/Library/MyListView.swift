import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Mi lista": Favoritos / Pendientes / Viendo / Vistos with swipe actions.
struct MyListView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case favorites, pending, watching, watched
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .favorites: "Favoritos"
            case .pending: "Pendientes"
            case .watching: "Viendo"
            case .watched: "Vistos"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent, title, score
        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .recent: "Recientes"
            case .title: "Título"
            case .score: "Puntuación"
            }
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var segment: Segment = .watching
    @State private var sort: Sort = .recent
    @State private var showsSettings = false
    @State private var pendingError: String?

    var body: some View {
        List {
            Text(items.count == 1 ? "1 serie" : "\(items.count) series")
                .font(.footnote).foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
            ForEach(items) { item in
                Button { router.open(item.anime, source: "library-\(item.anime.malId)", remembering: deps.summaries) } label: {
                    LibraryRow(item: item)
                }
                .buttonStyle(.plain)
                .zoomSource("library-\(item.anime.malId)", cornerRadius: Theme.Radius.thumb)
                .accessibilityIdentifier("library-row-\(item.anime.malId)")
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.Spacing.l, bottom: 10, trailing: Theme.Spacing.l))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if item.entry.status == .watching {
                        Button("+1", systemImage: "plus") { library.increment(for: item.anime) }.tint(Theme.accent)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(item.entry.favorite ? "Quitar favorito" : "Favorito", systemImage: item.entry.favorite ? "heart.slash" : "heart") {
                        run { _ = try await library.toggleFavorite(for: item.anime) }
                    }
                    .tint(Theme.favorite)
                    Button("Quitar", systemImage: "trash", role: .destructive) {
                        run { try await library.remove(item.anime.malId) }
                    }
                }
                .contextMenu {
                    ForEach([WatchStatus.pending, .watching, .watched], id: \.self) { status in
                        Button(status.spanish, systemImage: status == item.entry.status ? "checkmark" : "") {
                            run { _ = try await library.setStatus(status, for: item.anime) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.snappy, value: library.version)
        .animation(.snappy, value: segment)
        .scrollDisabled(items.isEmpty)
        .overlay {
            if items.isEmpty {
                if library.isLoading {
                    ProgressView()
                } else {
                    EmptyStateView(
                        title: "Nada aquí todavía",
                        message: emptyMessage,
                        systemImage: "bookmark",
                        actionTitle: "Explorar temporada"
                    ) { router.tab = .season }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            Picker("Lista", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .navigationTitle("Mi lista")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Ordenar", systemImage: "arrow.up.arrow.down") {
                    Picker("Ordenar", selection: $sort) { ForEach(Sort.allCases) { Text($0.label).tag($0) } }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { AvatarButton { showsSettings = true } }.sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable { await library.load() }
        .alert("No se pudo guardar", isPresented: Binding(get: { pendingError != nil }, set: {
            if !$0 {
                pendingError = nil
            }
        })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(pendingError ?? "") }
    }

    private var items: [RecAnimeCore.LibraryItem] {
        let base: [RecAnimeCore.LibraryItem] = switch segment {
        case .favorites: library.groups.favorites
        case .pending: library.groups.pending
        case .watching: library.groups.watching
        case .watched: library.groups.watched
        }
        switch sort {
        case .recent: return base
        case .title: return base.sorted { $0.anime.title.localizedCaseInsensitiveCompare($1.anime.title) == .orderedAscending }
        case .score: return base.sorted { ($0.anime.score ?? 0) > ($1.anime.score ?? 0) }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch segment {
        case .favorites: "Marca un anime con el corazón para verlo aquí."
        case .pending: "Guarda lo que quieres ver más adelante."
        case .watching: "Cuando empieces una serie aparecerá aquí con tu progreso."
        case .watched: "Las temporadas que termines se guardan aquí."
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await work() } catch let error as APIError { pendingError = error.userMessage } catch {
                pendingError = error.localizedDescription
            }
        }
    }
}

struct LibraryRow: View {
    let item: RecAnimeCore.LibraryItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PosterImage(url: item.anime.imageURL, width: 56, height: 84, cornerRadius: Theme.Radius.thumb)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.anime.title).font(.headline).lineLimit(2)
                HStack(spacing: Theme.Spacing.s) {
                    StatusBadge(LocalizedStringKey(item.entry.status.spanish), color: Theme.status(item.entry.status.rawValue))
                    if item.entry.status != .pending {
                        Text(item.progress.episodesTotal.map { "ep \(item.entry.episodesWatched)/\($0)" } ?? "ep \(item.entry.episodesWatched)")
                            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if item.entry.status == .watching {
                    ProgressPill(watched: item.entry.episodesWatched, total: item.progress.episodesTotal)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: item.entry.favorite ? "heart.fill" : "heart")
                .foregroundStyle(item.entry.favorite ? Theme.favorite : Color(.tertiaryLabel))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: item.entry.favorite)
                .accessibilityLabel(item.entry.favorite ? "Favorito" : "No favorito")
        }
        .contentShape(Rectangle())
    }
}
