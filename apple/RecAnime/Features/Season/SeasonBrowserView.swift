import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Year list → season chips → grid.
struct SeasonBrowserView: View {
    let api: any RecAnimeAPI
    @State private var years: [SeasonIndex] = []
    @State private var error: APIError?

    var body: some View {
        List {
            ForEach(years) { year in
                Section(String(year.year)) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(year.seasons, id: \.self) { season in
                            NavigationLink(value: Route.seasonGrid(.specific(year: year.year, season: season))) {
                                Text(SeasonKind.localizedSeason(season))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .background(Theme.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if years.isEmpty {
                if let error {
                    EmptyStateView(
                        title: "No se pudo cargar",
                        message: LocalizedStringKey(error.userMessage),
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "Reintentar"
                    ) { Task { await load() } }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Explorar")
        .task { await load() }
    }

    private func load() async {
        do {
            years = try await api.seasonsIndex()
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .network(code: -1)
        }
    }
}
