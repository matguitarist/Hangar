import Foundation
import Testing
@testable import HangarKit

// S-044
@Test func sessionsGroupByWeekForTwelveWeeks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    let now = Date(timeIntervalSince1970: 1_795_000_000) // a Wednesday
    let sessions = [
        PlaySession(start: now.addingTimeInterval(-3600), length: 3600),
        PlaySession(start: now.addingTimeInterval(-7200), length: 1800),
        PlaySession(start: now.addingTimeInterval(-8 * 86400), length: 7200),
        PlaySession(start: now.addingTimeInterval(-200 * 86400), length: 9000),
    ]
    let weeks = PlayHistory.weeks(sessions, now: now, calendar: calendar)
    #expect(weeks.count == 12)
    #expect(weeks.last?.seconds == 5400)
    #expect(weeks[10].seconds == 7200)
    #expect(weeks.map(\.seconds).reduce(0, +) == 12600)
    #expect(zip(weeks, weeks.dropFirst()).allSatisfy { $0.start < $1.start })
}

@Test func olderLibrariesOpenWithoutSessions() throws {
    let game = try JSONDecoder().decode(Game.self, from: Data(#"{"id":"a","title":"A","playtime":120}"#.utf8))
    #expect(game.sessions.isEmpty && game.playtime == 120)
}

@Test func aRescanKeepsTheSessions() {
    var library = LibraryFile()
    var game = Game(id: "g", title: "G", source: .macApp)
    game.sessions = [PlaySession(start: Date(), length: 60)]
    library.games = [game]
    library.merge(scanned: [Game(id: "g", title: "G", source: .macApp)])
    #expect(library.games.first?.sessions.count == 1)
}
