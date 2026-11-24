import Foundation
import Testing
@testable import HangarKit

// M7 check-in: a rescan and a move keep everything the person did.
@Test func aRescanKeepsEveryPersonalField() {
    var game = Game(id: "g", title: "G", source: .macApp)
    game.playtime = 99
    game.lastPlayed = Date(timeIntervalSince1970: 5)
    game.sessions = [PlaySession(start: Date(timeIntervalSince1970: 1), length: 99)]
    game.record(.crashed, played: 3)
    game.customCover = "/c.png"
    game.options.arguments = "-x"
    game.added = Date(timeIntervalSince1970: 2)
    var library = LibraryFile(games: [game])
    library.merge(scanned: [Game(id: "g", title: "G", source: .macApp)])
    #expect(library.games.first == game)
}
