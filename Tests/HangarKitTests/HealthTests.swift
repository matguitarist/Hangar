import Foundation
import Testing
@testable import HangarKit

// S-042
@Test func eachHealthRuleFindsItsIssue() {
    var steamGame = Game(id: "s", title: "Steam Game", source: .crossOver)
    steamGame.steamID = "1"
    steamGame.bottle = "Steam"
    let moved = Game(id: "m", title: "Moved", source: .macApp)
    let saved = Game(id: "a", title: "Saved", source: .macApp)
    let backedUp = Game(id: "b", title: "Backed Up", source: .macApp)
    let facts = HealthFacts(games: [steamGame, moved, saved, backedUp], missingFiles: ["m"], unreadableBottles: ["Empty"],
                            signedOutBottles: ["Steam", "Other"], gamesWithSaves: ["a", "b", "m"], gamesWithBackups: ["b"])
    let issues = LibraryHealth.issues(facts)
    #expect(issues == [.filesMoved(gameID: "m"), .bottleUnreadable(bottle: "Empty"), .signedOut(bottle: "Steam"), .neverBackedUp(gameID: "a")])
}

@Test func aHealthyLibraryHasNoIssues() {
    #expect(LibraryHealth.issues(HealthFacts(games: [Game(id: "x", title: "X", source: .macApp)])).isEmpty)
}
