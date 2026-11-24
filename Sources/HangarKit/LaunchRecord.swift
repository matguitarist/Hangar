import Foundation

/// How a launch went (S-045), kept with the game.
public struct LaunchRecord: Codable, Sendable, Hashable {
    public enum Outcome: String, Codable, Sendable {
        case worked, quitRightAway, crashed, didntStart
        /// The tile warns when the last launch didn't work.
        public var failed: Bool { self != .worked }
    }

    public var outcome: Outcome
    public var date: Date
    /// Seconds it ran, for "crashed after 4 s".
    public var played: TimeInterval

    public init(outcome: Outcome, date: Date, played: TimeInterval = 0) {
        self.outcome = outcome
        self.date = date
        self.played = played
    }
}

extension Game {
    /// Keeps a launch's result and counts it.
    public mutating func record(_ outcome: LaunchRecord.Outcome, at date: Date = Date(), played: TimeInterval = 0) {
        lastLaunch = LaunchRecord(outcome: outcome, date: date, played: played)
        launches += 1
    }
}
