import Foundation
import Testing
@testable import HangarKit

// S-043
@Test func eachFilterIsARule() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var never = Game(id: "n", title: "Never", source: .macApp)
    never.path = "/Applications/Never.app"
    var old = Game(id: "o", title: "Old", source: .macApp)
    old.lastPlayed = now.addingTimeInterval(-200 * 86400)
    old.playtime = 3600
    var recent = Game(id: "r", title: "Recent", source: .crossOver)
    recent.lastPlayed = now.addingTimeInterval(-3 * 86400)
    recent.playtime = 60
    recent.bottle = "Steam"
    recent.runner = .crossOver
    let games = [never, old, recent]
    func names(_ f: GameFilter) -> [String] { games.filter { f.matches($0, now: now, macVersions: ["r"]) }.map(\.title) }
    #expect(names(.neverPlayed) == ["Never"])
    #expect(names(.notPlayedRecently) == ["Old"])
    #expect(names(.windows) == ["Recent"])
    #expect(names(.mac) == ["Never", "Old"])
    #expect(names(.hasMacVersion) == ["Recent"])
}
