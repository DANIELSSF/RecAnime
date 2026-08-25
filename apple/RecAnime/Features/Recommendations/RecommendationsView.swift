import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Live community recommendation pairs from MyAnimeList.
struct RecommendationsView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @State private var loader: PagedLoader<Recommendation>
    @State private var showsSettings = false

    init(api: any RecAnimeAPI) {
        _loader = State(initialValue: PagedLoader { page in try await api.recommendations(page: page) })
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.l) {
                ForEach(loader.items) { rec in
                    RecommendationCard(recommendation: rec) { entry in
                        deps.summaries.remember(entry)
                        router.open(anime: entry.malId, source: "rec-\(rec.id)-\(entry.malId)")
                    }
                    .task { await loader.loadMoreIfNeeded(currentItem: rec) }
                }
                if loader.state == .loadingMore {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .overlay {
            if loader.items.isEmpty {
                switch loader.state {
                case .loading: ProgressView()
                case let .failed(error):
                    EmptyStateView(
                        title: "Sin recomendaciones",
                        message: LocalizedStringKey(error.userMessage),
                        systemImage: "sparkles",
                        actionTitle: "Reintentar"
                    ) { Task { await loader.loadFirst() } }
                default: EmptyView()
                }
            }
        }
        .navigationTitle("Descubrir")
        .navigationSubtitle(loader.meta?.stale == true ? "Recomendaciones de MyAnimeList · sin conexión" : "Recomendaciones de MyAnimeList · en vivo")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AvatarButton { showsSettings = true } }.sharedBackgroundVisibility(.hidden) }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable { await loader.loadFirst() }
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    let onSelect: (RecommendationEntry) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("SI TE GUSTÓ · TE GUSTARÁ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(Array(recommendation.entries.prefix(2).enumerated()), id: \.element.id) { index, entry in
                    if index == 1 {
                        Image(systemName: "arrow.right")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(height: 150)
                    }
                    Button { onSelect(entry) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterImage(url: entry.imageURL, width: 100, height: 150)
                                .zoomSource("rec-\(recommendation.id)-\(entry.malId)")
                            Text(entry.title).font(.footnote.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(
                                width: 100,
                                alignment: .leading
                            )
                            if let overlay = entry.library {
                                StatusBadge(LocalizedStringKey(overlay.status.spanish), color: Theme.status(overlay.status.rawValue))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(recommendation.content)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 4)
            if recommendation.content.count > 220 {
                Button(expanded ? "Menos" : "Más") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.subheadline.weight(.semibold))
            }
            Text("por \(recommendation.user.username)\(recommendation.date.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? "")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.l)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
