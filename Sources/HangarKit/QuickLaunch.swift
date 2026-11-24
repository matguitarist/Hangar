import Foundation

/// The menu bar's quick launch (S-026): the games played last, ready to play again.
public enum QuickLaunch {
    public static let recentLimit = 5

    /// Games played before, the latest first, without the ones running now.
    public static func recent(_ games: [Game], running: Set<String>, limit: Int = recentLimit) -> [Game] {
        Array(GameSort.recentlyPlayed.sorted(games.filter { $0.lastPlayed != nil && !running.contains($0.id) }).prefix(limit))
    }
}
