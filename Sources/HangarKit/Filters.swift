import Foundation

/// A smart filter on any page (S-043). Combines with search and sort.
public enum GameFilter: String, Sendable, CaseIterable {
    case neverPlayed, notPlayedRecently, windows, mac, hasMacVersion

    /// "Not Played in 6 Months": played once, not since.
    public static let recentDays: Double = 182

    /// `macVersions` holds the Windows games a store or AppleGamingWiki says have a Mac version.
    public func matches(_ game: Game, now: Date = Date(), macVersions: Set<String> = []) -> Bool {
        switch self {
        case .neverPlayed: game.playtime == 0 && game.lastPlayed == nil
        case .notPlayedRecently: game.lastPlayed.map { now.timeIntervalSince($0) > Self.recentDays * 86400 } ?? false
        case .windows: game.isWindows
        case .mac: !game.isWindows
        case .hasMacVersion: game.isWindows && macVersions.contains(game.id)
        }
    }
}
