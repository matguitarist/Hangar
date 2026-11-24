import Foundation
import Testing
@testable import HangarKit

// S-045
@Test func eachLaunchIsKeptAndCounted() throws {
    var game = Game(id: "g", title: "G", source: .macApp)
    game.record(.worked, played: 600)
    game.record(.crashed, played: 4)
    #expect(game.launches == 2)
    #expect(game.lastLaunch?.outcome == .crashed && game.lastLaunch?.played == 4)
    #expect(game.lastLaunch?.outcome.failed == true)
    let copy = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
    #expect(copy.launches == 2 && copy.lastLaunch == game.lastLaunch)
    let old = try JSONDecoder().decode(Game.self, from: Data(#"{"id":"a","title":"A"}"#.utf8))
    #expect(old.launches == 0 && old.lastLaunch == nil)
}

@Test func aRescanKeepsTheLaunchRecord() {
    var library = LibraryFile()
    var game = Game(id: "g", title: "G", source: .macApp)
    game.record(.didntStart)
    library.games = [game]
    library.merge(scanned: [Game(id: "g", title: "G", source: .macApp)])
    #expect(library.games.first?.lastLaunch?.outcome == .didntStart && library.games.first?.launches == 1)
}
