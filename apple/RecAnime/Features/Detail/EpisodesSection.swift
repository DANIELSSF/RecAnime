import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Episodios": the first page inline (up to 6 rows) with a link to the full paged list.
/// Tapping a row marks every episode up to it as watched — the one-tap alternative to +1.
struct EpisodesSection: View {
    @Environment(LibraryStore.self) private var library
    let detail: AnimeDetail
    let api: any RecAnimeAPI
    /// Hands the loaded titles back so the episode picker can label its wheel.
    let onTitles: ([Int: String]) -> Void
    let report: (String) -> Void
    @State private var episodes: [Episode] = []
    @State private var error: APIError?
    @State private var isLoading = false

    /// Rows rendered inline; the rest lives behind "Ver todos".
    private static let previewLimit = 6

    private var watched: Int {
        library.items[detail.malId]?.entry.episodesWatched ?? 0
    }

    private var preview: [Episode] {
        Array(episodes.prefix(Self.previewLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Episodios") {
                if !episodes.isEmpty {
                    NavigationLink("Ver todos") {
                        EpisodesListView(detail: detail, api: api)
                    }
                    .accessibilityIdentifier("detail.episodes.all")
                }
            }
            content
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if episodes.isEmpty {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).frame(minHeight: 60)
            } else if let error {
                InlineRetryRow(message: error.userMessage) { Task { await load() } }
            } else {
                Text("MyAnimeList aún no lista los episodios de este título.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.l)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(preview) { episode in
                    EpisodeRow(episode: episode, isWatched: episode.number <= watched) { mark(episode) }
                    if episode.id != preview.last?.id {
                        Divider().padding(.leading, Theme.Spacing.xxl + Theme.Spacing.l)
                    }
                }
            }
        }
    }

    private func load() async {
        guard episodes.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.episodes(detail.malId, page: 1)
            episodes = response.data
            error = nil
            onTitles(Dictionary(response.data.map { ($0.number, $0.title) }, uniquingKeysWith: { first, _ in first }))
        } catch let apiError as APIError where apiError == .cancelled {
            // The page went away; leave the section as it was.
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .network(code: -1)
        }
    }

    /// "Marcar visto hasta aquí": absolute value, so tapping a lower episode also rewinds progress.
    private func mark(_ episode: Episode) {
        Task {
            do {
                _ = try await library.setEpisodes(episode.number, for: detail.summary)
            } catch let error as APIError {
                report(error.userMessage)
            } catch {
                report(error.localizedDescription)
            }
        }
    }
}

/// Full episode list behind "Ver todos", paged as the user scrolls.
struct EpisodesListView: View {
    @Environment(LibraryStore.self) private var library
    let detail: AnimeDetail
    @State private var loader: PagedLoader<Episode>
    @State private var actionError: String?

    init(detail: AnimeDetail, api: any RecAnimeAPI) {
        self.detail = detail
        let malID = detail.malId
        _loader = State(initialValue: PagedLoader { page in try await api.episodes(malID, page: page) })
    }

    private var watched: Int {
        library.items[detail.malId]?.entry.episodesWatched ?? 0
    }

    var body: some View {
        List {
            ForEach(loader.items) { episode in
                EpisodeRow(episode: episode, isWatched: episode.number <= watched) { mark(episode) }
                    .listRowInsets(EdgeInsets())
                    .task { await loader.loadMoreIfNeeded(currentItem: episode) }
            }
            footer
        }
        .listStyle(.plain)
        .overlay { placeholder }
        .navigationTitle("Episodios")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
        .refreshable { await loader.loadFirst() }
        .alert("No se pudo guardar", isPresented: Binding(get: { actionError != nil }, set: {
            if !$0 {
                actionError = nil
            }
        })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    @ViewBuilder
    private var footer: some View {
        switch loader.state {
        case .loadingMore:
            ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
        case let .failed(error) where !loader.items.isEmpty:
            InlineRetryRow(message: error.userMessage) { Task { await loader.retryMore() } }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if loader.items.isEmpty {
            switch loader.state {
            case let .failed(error):
                EmptyStateView(
                    title: "No se pudo cargar",
                    message: LocalizedStringKey(error.userMessage),
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Reintentar"
                ) { Task { await loader.retryMore() } }
            case .exhausted:
                ContentUnavailableView(
                    "Sin episodios",
                    systemImage: "list.bullet.rectangle",
                    description: Text("MyAnimeList aún no lista los episodios de este título.")
                )
            default:
                ProgressView()
            }
        }
    }

    private func mark(_ episode: Episode) {
        Task {
            do {
                _ = try await library.setEpisodes(episode.number, for: detail.summary)
            } catch let error as APIError {
                actionError = error.userMessage
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

/// One episode: number, title, air date and filler/recap tags; the whole row marks progress.
private struct EpisodeRow: View {
    let episode: Episode
    let isWatched: Bool
    let action: () -> Void

    private var title: String {
        episode.title.isEmpty ? "Episodio \(episode.number)" : episode.title
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Text("\(episode.number)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isWatched ? Theme.accent : Color.secondary)
                    .frame(minWidth: Theme.Spacing.xxl, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline).lineLimit(2)
                    HStack(spacing: 6) {
                        if let aired = episode.aired {
                            Text(aired.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if episode.filler {
                            StatusBadge("Relleno", color: Theme.statusPending)
                        }
                        if episode.recap {
                            StatusBadge("Resumen", color: Theme.statusPending)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isWatched ? Theme.statusWatched : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Episodio \(episode.number), \(title)")
        .accessibilityHint("Marcar visto hasta aquí")
        .accessibilityAddTraits(isWatched ? .isSelected : [])
        .accessibilityIdentifier("detail.episode.row.\(episode.number)")
    }
}
