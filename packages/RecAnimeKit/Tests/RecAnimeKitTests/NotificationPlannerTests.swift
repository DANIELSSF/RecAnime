import Foundation
@testable import RecAnimeCore
import Testing

@Suite("Notification planner")
struct NotificationPlannerTests {
    let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17T...Z

    func item(malId: Int, title: String, next: Date, nextEpisode: Int?, total: Int?, watched: Int = 3) -> ScheduleItem {
        ScheduleItem(
            malId: malId,
            title: title,
            imageUrl: "",
            broadcast: nil,
            nextAiringAt: next,
            nextEpisodeNumber: nextEpisode,
            latestEpisode: nil,
            episodesTotal: total,
            episodesWatched: watched,
            remaining: nil,
            status: nil,
            airing: true,
            reason: nil
        )
    }

    @Test("weekly expansion stops at the episode total and stays inside the horizon")
    func weeklyExpansion() {
        let first = now.addingTimeInterval(3600)
        let plan = NotificationPlanner.plan(
            schedule: [item(malId: 1, title: "A", next: first, nextEpisode: 10, total: 12)],
            now: now,
            settings: .default
        )
        #expect(plan.map(\.episode) == [10, 11, 12])
        #expect(plan.map(\.id) == ["ep.1.10", "ep.1.11", "ep.1.12"])
        #expect(plan[1].fireDate == first.addingTimeInterval(7 * 86400))
        #expect(plan[0].title == "Nuevo episodio: A")
        #expect(plan[0].body == "Ep. 10 ya disponible · Llevas 3/12")
    }

    @Test("offset is applied and past slots are dropped")
    func offsetAndPast() {
        let past = now.addingTimeInterval(-600)
        let plan = NotificationPlanner.plan(
            schedule: [item(malId: 2, title: "B", next: past, nextEpisode: 1, total: nil)],
            now: now,
            settings: NotificationSettings(enabled: true, offsetSeconds: 900)
        )
        // -600 s + 900 s offset = +300 s -> still in the future, so the first slot survives.
        #expect(plan.first?.fireDate == past.addingTimeInterval(900))
        #expect(plan.first?.episode == 1)
        let dropped = NotificationPlanner.plan(
            schedule: [item(malId: 2, title: "B", next: now.addingTimeInterval(-7200), nextEpisode: 1, total: nil)],
            now: now,
            settings: .default
        )
        #expect(dropped.first?.episode == 2)
    }

    @Test("limit keeps the soonest notifications across anime")
    func limit() throws {
        var schedule: [ScheduleItem] = []
        for i in 0 ..< 10 {
            schedule.append(item(malId: i, title: "S\(i)", next: now.addingTimeInterval(Double(i + 1) * 600), nextEpisode: 1, total: nil))
        }
        let plan = NotificationPlanner.plan(schedule: schedule, now: now, settings: .default, horizon: 30 * 86400, limit: 12)
        #expect(plan.count == 12)
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
        #expect(try #require(plan.last?.fireDate) <= now.addingTimeInterval(7 * 86400 + 6000))
    }

    @Test("disabled settings produce nothing; unknown episode numbers get date-based ids")
    func disabledAndUnknownEpisode() {
        let disabled = NotificationPlanner.plan(
            schedule: [item(malId: 3, title: "C", next: now.addingTimeInterval(60), nextEpisode: 1, total: nil)],
            now: now,
            settings: NotificationSettings(enabled: false)
        )
        #expect(disabled.isEmpty)
        let plan = NotificationPlanner.plan(
            schedule: [item(malId: 3, title: "C", next: now.addingTimeInterval(60), nextEpisode: nil, total: nil)],
            now: now,
            settings: .default,
            horizon: 86400
        )
        #expect(plan.count == 1)
        #expect(plan[0].id.hasPrefix("ep.3.2026"))
        #expect(plan[0].body.hasPrefix("Nuevo episodio disponible"))
    }
}
