import Foundation
import Testing
@testable import HangarKit

private let answers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Details")

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "hangar-details-\(UUID().uuidString)")
}

// S-031
@Test func steamsAnswerBecomesDetails() throws {
    let data = try Data(contentsOf: answers.appending(path: "steam-367520.json"))
    let details = try #require(SteamDetails.parse(data, appID: "367520"))
    #expect(details.source == .steam)
    #expect(details.summary.hasPrefix("Forge your own path in Hollow Knight!"))
    #expect(details.developers == ["Team Cherry"] && details.publishers == ["Team Cherry"])
    #expect(details.genres == ["Action", "Adventure", "Indie"])
    #expect(details.releaseText == "24 Feb, 2017")
    #expect(details.url?.absoluteString.contains("367520") == true)
    #expect(SteamDetails.parse(Data(#"{"1":{"success":false}}"#.utf8), appID: "1") == nil)
}

@Test func steamIsAskedInTheAppsLanguage() {
    #expect(SteamDetails.language(for: "fr") == "french")
    #expect(SteamDetails.language(for: "en") == "english")
    #expect(SteamDetails.url(appID: "367520", language: "french").query()?.contains("l=french") == true)
}

@Test func storeTextBecomesPlainText() {
    #expect(PlainText.from(html: "Fast &amp; fun<br>Second line<br/><br/><b>Bold</b> &quot;quoted&quot;") == "Fast & fun\nSecond line\n\nBold \"quoted\"")
    #expect(PlainText.paragraphs("One\r\n\r\n\r\nTwo  \n") == "One\n\nTwo")
}

@Test func theGamesDBsBestMatchWithNames() async throws {
    let cache = GameDetailsCache(folder: temporaryFolder(), key: "k", fetch: GameDetailsCache.folder(answers))
    let details = try #require(await cache.details(title: "Moonlit Harbor", mac: false))
    #expect(details.source == .theGamesDB)
    #expect(details.summary == "A lighthouse keeper's quiet mystery on a foggy coast.\n\nExplore the harbor by night.")
    #expect(details.developers == ["Tidewater Games"] && details.publishers == ["Lantern Press"])
    #expect(details.genres == ["Adventure", "Puzzle"])
    #expect(details.releaseDate.map { TheGamesDB.day.string(from: $0) } == "2019-03-14")
    #expect(details.url?.absoluteString == "https://thegamesdb.net/game.php?id=900001")
}

@Test func withoutAKeyTheGamesDBIsNotAsked() async {
    let cache = GameDetailsCache(folder: temporaryFolder(), fetch: { _ in Issue.record("asked"); throw URLError(.badURL) })
    #expect(await cache.details(title: "Moonlit Harbor", mac: false) == nil)
}

@Test func aMacGameLooksOnTheMacFirst() {
    let games = [TheGamesDB.Game(id: 1, title: "Tiny Tactics", alternates: [], platform: 1, overview: "", released: nil, developers: [], publishers: [], genres: []),
                 TheGamesDB.Game(id: 2, title: "Tiny Tactics", alternates: [], platform: 37, overview: "", released: nil, developers: [], publishers: [], genres: [])]
    #expect(TheGamesDB.bestMatch(games, title: "Tiny Tactics", platforms: [37, 1])?.id == 2)
    #expect(TheGamesDB.searchURL(title: "Tiny Tactics", platforms: [37, 1], key: "k").query()?.contains("filter%5Bplatform%5D=37,1") == true
            || TheGamesDB.searchURL(title: "Tiny Tactics", platforms: [37, 1], key: "k").query()?.contains("filter[platform]=37,1") == true)
}

@Test func detailsAreKeptAMonthAndOfflineUsesTheCache() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calls = Calls()
    let clock = Now()
    let fixture = GameDetailsCache.folder(answers)
    let online = GameDetailsCache(folder: folder, fetch: { request in calls.add(); return try await fixture(request) }, now: { clock.date })
    #expect(await online.details(steamID: "367520", language: "english")?.developers == ["Team Cherry"])
    #expect(await online.details(steamID: "367520", language: "english") != nil)
    #expect(calls.count == 1)
    clock.date = clock.date.addingTimeInterval(31 * 86400)
    let offline = GameDetailsCache(folder: folder, fetch: { _ in throw URLError(.notConnectedToInternet) }, now: { clock.date })
    #expect(await offline.details(steamID: "367520", language: "english")?.developers == ["Team Cherry"])
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.withLock { n += 1 } }
    var count: Int { lock.withLock { n } }
}

private final class Now: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
