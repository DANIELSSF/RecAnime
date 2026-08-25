import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Browse by season: pick the season on top, then tap a year. One destination per row, so the
/// navigation stack only ever grows by one screen.
struct SeasonBrowserView: View {
    enum Season: String, CaseIterable, Identifiable {
        case winter, spring, summer, fall
        var id: String {
            rawValue
        }

        var title: String {
            SeasonKind.localizedSeason(rawValue)
        }

        var symbol: String {
            switch self {
            case .winter: "snowflake"
            case .spring: "leaf"
            case .summer: "sun.max"
            case .fall: "wind"
            }
        }
    }

    let api: any RecAnimeAPI
    @State private var years: [SeasonIndex] = []
    @State private var season: Season = SeasonBrowserView.currentSeason()
    @State private var error: APIError?
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(availableYears, id: \.self) { year in
                NavigationLink(value: Route.seasonGrid(.specific(year: year, season: season.rawValue))) {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: season.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accentSoft, in: Circle())
                            .accessibilityHidden(true)
                        Text("\(season.title) \(String(year))")
                            .font(.body.weight(.medium))
                        if year == Calendar.current.component(.year, from: .now) {
                            StatusBadge("Este año", color: Theme.accent)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(availableYears.isEmpty)
        .overlay {
            if years.isEmpty {
                if isLoading {
                    ProgressView()
                } else if let error {
                    EmptyStateView(
                        title: "No se pudo cargar",
                        message: LocalizedStringKey(error.userMessage),
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "Reintentar"
                    ) { Task { await load() } }
                }
            } else if availableYears.isEmpty {
                ContentUnavailableView("Sin datos para esta temporada", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .safeAreaBar(edge: .top) {
            Picker("Temporada", selection: $season) {
                ForEach(Season.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .navigationTitle("Explorar")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: season)
        .task { await load() }
    }

    /// Years (newest first) that have the selected season on MyAnimeList.
    private var availableYears: [Int] {
        years.filter { $0.seasons.contains(season.rawValue) }.map(\.year).sorted(by: >)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            years = try await api.seasonsIndex()
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .network(code: -1)
        }
    }

    static func currentSeason(now: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: now) {
        case 1 ... 3: .winter
        case 4 ... 6: .spring
        case 7 ... 9: .summer
        default: .fall
        }
    }
}
