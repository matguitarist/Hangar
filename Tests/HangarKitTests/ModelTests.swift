import Foundation
import Testing
@testable import HangarKit

@Test func gameSurvivesJSON() throws {
    let game = Game(id: "steam:1546710", title: "Vernal Edge", source: .crossOver)
    let data = try JSONEncoder().encode(game)
    #expect(try JSONDecoder().decode(Game.self, from: data) == game)
}
