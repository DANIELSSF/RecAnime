import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Similares": what other MyAnimeList users recommend after this title, sorted by votes.
/// Non-essential content: a failed fetch simply leaves the section out.
struct SimilarSection: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let malID: Int
    let api: any RecAnimeAPI
    @State private var recommendations: [AnimeRecommendation] = []

    /// Enough to scroll through without paging a secondary section.
    private static let limit = 20

    var body: some View {
        Group {
            if !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader("Similares")
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ForEach(recommendations.prefix(Self.limit)) { recommendation in
                                card(recommendation)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .task { await load() }
    }

    private func card(_ recommendation: AnimeRecommendation) -> some View {
        let entry = recommendation.anime
        let source = "similar-\(malID)-\(entry.malId)"
        return Button {
            deps.summaries.remember(entry)
            router.open(anime: entry.malId, source: source)
        } label: {
            PosterCard(title: entry.title, subtitle: votesLabel(recommendation.votes), imageURL: entry.imageURL)
        }
        .buttonStyle(.plain)
        .zoomSource(source)
        .accessibilityIdentifier("poster-similar-\(entry.malId)")
    }

    private func votesLabel(_ votes: Int) -> String {
        votes == 1 ? "1 voto" : "\(votes) votos"
    }

    private func load() async {
        guard recommendations.isEmpty else { return }
        recommendations = await (try? api.animeRecommendations(malID)) ?? []
    }
}
