import Foundation

/// User preferences for episode notifications.
public struct NotificationSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// Delay after the broadcast slot (0, 15 min or 60 min).
    public var offsetSeconds: TimeInterval

    public init(enabled: Bool = true, offsetSeconds: TimeInterval = 0) {
        self.enabled = enabled
        self.offsetSeconds = offsetSeconds
    }

    public static let `default` = NotificationSettings()
}

/// One local notification to schedule. Identifiers are deterministic so re-planning is idempotent:
/// `ep.<malId>.<episode|"x">.<yyyyMMddHHmm UTC of fireDate>`. The fire date is part of the id on
/// purpose — a corrected airing time yields a new id, so the scheduler diff drops the stale one
/// instead of keeping the notification pinned to the old slot.
public struct PlannedNotification: Hashable, Sendable, Identifiable {
    public let id: String
    public let malID: Int
    public let episode: Int?
    public let fireDate: Date
    public let title: String
    public let body: String

    public init(id: String, malID: Int, episode: Int?, fireDate: Date, title: String, body: String) {
        self.id = id
        self.malID = malID
        self.episode = episode
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

/// Pure planner: expands each watched, airing anime into weekly notifications within a horizon,
/// keeps the soonest `limit` (iOS allows 64 pending local notifications) and never fires in the past.
public enum NotificationPlanner {
    /// Every planned id starts with this; the app uses it to tell its own pending requests apart.
    public static let idPrefix = "ep."

    public static func plan(
        schedule: [ScheduleItem],
        now: Date,
        settings: NotificationSettings,
        horizon: TimeInterval = 21 * 86400,
        limit: Int = 60
    ) -> [PlannedNotification] {
        guard settings.enabled else { return [] }
        var out: [PlannedNotification] = []
        let end = now.addingTimeInterval(horizon)
        for item in schedule {
            guard let next = item.nextAiringAt else { continue }
            var fire = next.addingTimeInterval(settings.offsetSeconds)
            var episode = item.nextEpisodeNumber
            var guardCounter = 0
            while fire < end, guardCounter < 60 {
                guardCounter += 1
                if let total = item.episodesTotal, let ep = episode, ep > total {
                    break
                }
                if fire > now {
                    out.append(make(item: item, episode: episode, fireDate: fire))
                }
                fire = fire.addingTimeInterval(7 * 86400)
                if let ep = episode {
                    episode = ep + 1
                }
            }
        }
        out.sort { $0.fireDate < $1.fireDate }
        if out.count > limit {
            out.removeLast(out.count - limit)
        }
        return out
    }

    static func make(item: ScheduleItem, episode: Int?, fireDate: Date) -> PlannedNotification {
        let suffix = episode.map { "\($0)" } ?? "x"
        let progress = if let total = item.episodesTotal {
            "Llevas \(item.episodesWatched)/\(total)"
        } else {
            "Llevas \(item.episodesWatched)"
        }
        let body = episode.map { "Ep. \($0) ya disponible · \(progress)" } ?? "Nuevo episodio disponible · \(progress)"
        return PlannedNotification(
            id: "\(idPrefix)\(item.malId).\(suffix).\(stamp(fireDate))",
            malID: item.malId,
            episode: episode,
            fireDate: fireDate,
            title: "Nuevo episodio: \(item.title)",
            body: body
        )
    }

    /// `yyyyMMddHHmm` in UTC. Built from `Calendar` instead of a shared `DateFormatter` so it stays
    /// value-only (Sendable) and locale-independent.
    static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
    }
}
