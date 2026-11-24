import Foundation
import Testing
@testable import HangarKit

// S-026
@Test func recentGamesAreTheLatestPlayedAndNotRunning() {
    func game(_ id: String, daysAgo: Double?) -> Game {
        var g = Game(id: id, title: id.uppercased(), source: .macApp)
        g.lastPlayed = daysAgo.map { Date(timeIntervalSince1970: 1_800_000_000 - $0 * 86400) }
        return g
    }
    let games = [game("a", daysAgo: 3), game("b", daysAgo: 1), game("never", daysAgo: nil), game("c", daysAgo: 2),
                 game("d", daysAgo: 9), game("e", daysAgo: 7), game("f", daysAgo: 8)]
    #expect(QuickLaunch.recent(games, running: []).map(\.id) == ["b", "c", "a", "e", "f"])
    #expect(QuickLaunch.recent(games, running: ["b"]).map(\.id) == ["c", "a", "e", "f", "d"])
    #expect(QuickLaunch.recent([game("never", daysAgo: nil)], running: []).isEmpty)
}
