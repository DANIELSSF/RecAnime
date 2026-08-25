import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Search tab (system search role): debounced query, recent searches.
struct SearchView: View {
    @Environment(Router.self) private var router
    let api: any RecAnimeAPI
    @State private var query = ""
    @State private var loader: PagedLoader<AnimeSummary>?
    @AppStorage("ra.recentSearches") private var recentData = Data()

    init(api: any RecAnimeAPI) {
        self.api = api
    }

    var body: some View {
        List {
            if let loader, trimmed.count >= 3 {
                ForEach(loader.items) { anime in
                    Button { remember(trimmed); router.open(anime: anime.malId) } label: { RankedAnimeRow(rank: nil, anime: anime) }
                        .buttonStyle(.plain)
                        .task { await loader.loadMoreIfNeeded(currentItem: anime) }
                }
                if loader.state == .loadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if !recents.isEmpty {
                Section("Recientes") {
                    ForEach(recents, id: \.self) { term in
                        Button(term, systemImage: "clock") { query = term }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        var list = recents
                        list.remove(atOffsets: offsets)
                        recents = list
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let loader, trimmed.count >= 3 {
                if loader.items.isEmpty {
                    switch loader.state {
                    case .loading: ProgressView()
                    case .exhausted: ContentUnavailableView.search(text: trimmed)
                    case let .failed(error):
                        EmptyStateView(
                            title: "No se pudo buscar",
                            message: LocalizedStringKey(error.userMessage),
                            systemImage: "wifi.exclamationmark",
                            actionTitle: "Reintentar"
                        ) { Task { await loader.loadFirst() } }
                    default: EmptyView()
                    }
                }
            } else if recents.isEmpty {
                ContentUnavailableView("Busca un anime", systemImage: "magnifyingglass", description: Text("Escribe al menos 3 letras."))
            }
        }
        .navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Buscar anime")
        .searchToolbarBehavior(.minimize)
        .task(id: trimmed) {
            guard trimmed.count >= 3 else { loader = nil; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let api = api
            let q = trimmed
            let fresh = PagedLoader<AnimeSummary> { page in try await api.search(q, page: page) }
            loader = fresh
            await fresh.loadFirst()
        }
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recents: [String] {
        get { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }
        nonmutating set { recentData = (try? JSONEncoder().encode(Array(newValue.prefix(10)))) ?? Data() }
    }

    private func remember(_ term: String) {
        var list = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        list.insert(term, at: 0)
        recents = list
    }
}
