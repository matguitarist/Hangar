import Foundation

/// One time the person played (S-044): when it started, and for how long.
public struct PlaySession: Codable, Sendable, Hashable {
    public var start: Date
    public var length: TimeInterval

    public init(start: Date, length: TimeInterval) {
        self.start = start
        self.length = length
    }
}

/// Hours played in one week.
public struct PlayWeek: Sendable, Hashable {
    public var start: Date
    public var seconds: TimeInterval
    public var hours: Double { seconds / 3600 }
}

public enum PlayHistory {
    /// Sessions kept per game: about ten years of daily play.
    public static let keep = 4000

    /// The last `count` weeks, oldest first, each with the time of the sessions that started in it.
    public static func weeks(_ sessions: [PlaySession], now: Date = Date(), count: Int = 12, calendar: Calendar = .current) -> [PlayWeek] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        var totals = [Date: TimeInterval]()
        for session in sessions {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: session.start)?.start else { continue }
            totals[week, default: 0] += session.length
        }
        return starts.map { PlayWeek(start: $0, seconds: totals[$0] ?? 0) }
    }

    /// Adds a finished launch's session, keeping the newest.
    public static func adding(_ session: PlaySession, to sessions: [PlaySession]) -> [PlaySession] {
        Array((sessions + [session]).suffix(keep))
    }
}
