import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Weekly airing calendar: one day at a time from `/v1/schedules?day=`, defaulting to today.
/// `AnimeSummary` carries no broadcast time, so the list shows the day only.
struct WeeklyScheduleView: View {
    /// The API's day keys, in the order the picker shows them (Monday first, as in Spain).
    enum Day: String, CaseIterable, Identifiable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday

        var id: String {
            rawValue
        }

        var short: String {
            switch self {
            case .monday: "Lun"
            case .tuesday: "Mar"
            case .wednesday: "Mié"
            case .thursday: "Jue"
            case .friday: "Vie"
            case .saturday: "Sáb"
            case .sunday: "Dom"
            }
        }

        var title: String {
            switch self {
            case .monday: "Lunes"
            case .tuesday: "Martes"
            case .wednesday: "Miércoles"
            case .thursday: "Jueves"
            case .friday: "Viernes"
            case .saturday: "Sábado"
            case .sunday: "Domingo"
            }
        }

        /// `Calendar` numbers weekdays from Sunday = 1, independent of the user's locale.
        static var today: Day {
            switch Calendar.current.component(.weekday, from: .now) {
            case 2: .monday
            case 3: .tuesday
            case 4: .wednesday
            case 5: .thursday
            case 6: .friday
            case 7: .saturday
            default: .sunday
            }
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let api: any RecAnimeAPI
    @State private var day: Day
    @State private var loader: PagedLoader<AnimeSummary>

    init(api: any RecAnimeAPI) {
        self.api = api
        let today = Day.today
        _day = State(initialValue: today)
        _loader = State(initialValue: PagedLoader { page in try await api.schedules(day: today.rawValue, page: page) })
    }

    var body: some View {
        List {
            ForEach(loader.items) { anime in
                Button { router.open(anime, source: "calendar-\(anime.malId)", remembering: deps.summaries) } label: {
                    RankedAnimeRow(rank: nil, anime: anime)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.Spacing.l, bottom: 10, trailing: Theme.Spacing.l))
                .zoomSource("calendar-\(anime.malId)", cornerRadius: Theme.Radius.thumb)
                .accessibilityIdentifier("calendar-row-\(anime.malId)")
                .task { await loader.loadMoreIfNeeded(currentItem: anime) }
            }
            if case let .failed(error) = loader.state, !loader.items.isEmpty {
                InlineRetryRow(message: error.userMessage) { Task { await loader.retryMore() } }
                    .listRowInsets(EdgeInsets())
            } else if loader.state == .loadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .scrollDisabled(loader.items.isEmpty)
        .overlay { placeholder }
        .safeAreaBar(edge: .top) { picker }
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(day.title)
        .refreshable { await loader.loadFirst() }
        .task {
            if loader.items.isEmpty {
                await loader.loadFirst()
            }
        }
        .onChange(of: day) { _, selected in
            let api = api
            Task { await loader.replace { page in try await api.schedules(day: selected.rawValue, page: page) } }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if loader.items.isEmpty {
            switch loader.state {
            case .loading, .loadingMore:
                ProgressView()
            case let .failed(error):
                EmptyStateView(
                    title: "No se pudo cargar",
                    message: LocalizedStringKey(error.userMessage),
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Reintentar"
                ) { Task { await loader.loadFirst() } }
            case .exhausted:
                ContentUnavailableView(
                    "Nada programado",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Ningún estreno este día. Prueba otro.")
                )
            case .idle:
                EmptyView()
            }
        }
    }

    private var picker: some View {
        Picker("Día", selection: $day) {
            ForEach(Day.allCases) { option in
                Text(option.short).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityIdentifier("calendar.day")
    }
}
