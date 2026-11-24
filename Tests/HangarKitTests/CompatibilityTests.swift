import Foundation
import Testing
@testable import HangarKit

private let pages = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/AppleGamingWiki")

// S-015
@Test func parsesTheCompatibilityTemplateForEachMethod() throws {
    let source = try String(contentsOf: pages.appending(path: "Hollow_Knight.txt"), encoding: .utf8)
    let c = try #require(Compatibility.parse(source, page: "Hollow_Knight"))
    #expect(c.entries.map(\.method) == [.native, .rosetta, .crossOver, .wine, .parallels])
    #expect(c.entries.map(\.rating) == [.perfect, .perfect, .perfect, .unknown, .perfect])
    #expect(c.entries[0].notes == "Added on patch version 1.5.12459 (further testing required)")
    #expect(c.entries[2].notes == "Perfect.")
    #expect(c.entries[4].notes.hasPrefix("Playable, although there is minor"))
    #expect(c.url.absoluteString == "https://www.applegamingwiki.com/wiki/Hollow_Knight")
}

@Test func notesLoseTheirWikiMarkup() throws {
    let source = try String(contentsOf: pages.appending(path: "Vernal_Edge.txt"), encoding: .utf8)
    let c = try #require(Compatibility.parse(source, page: "Vernal_Edge"))
    #expect(c.entries.map(\.method) == [.crossOver, .wine, .parallels])
    #expect(c.entries[0].rating == .playable)
    #expect(c.entries[0].notes == "Runs with D3DMetal. Set MSync on; see the CrossOver page.")
    #expect(Compatibility.parse("no template here", page: "X") == nil)
}

/// Counts fetches, and can go offline.
private final class Wiki: @unchecked Sendable {
    let lock = NSLock()
    var calls: [String] = []
    var offline = false

    func fetch(_ page: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        calls.append(page)
        if offline { throw URLError(.notConnectedToInternet) }
        return try? String(contentsOf: pages.appending(path: "\(page).txt"), encoding: .utf8)
    }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Test func theCacheIsUsedOfflineAndRefreshedAtMostOnceAWeek() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarAGW-\(UUID().uuidString)")
    let wiki = Wiki(), clock = Clock()
    let cache = CompatibilityCache(folder: folder, fetch: { try wiki.fetch($0) }, now: { clock.now })
    #expect(await cache.compatibility(for: "Hollow Knight")?.entries.count == 5)
    #expect(await cache.compatibility(for: "Hollow Knight") != nil)
    #expect(wiki.calls == ["Hollow_Knight"])
    clock.now += 6 * 86400
    _ = await cache.compatibility(for: "Hollow Knight")
    #expect(wiki.calls.count == 1)
    clock.now += 2 * 86400
    wiki.offline = true
    #expect(await cache.compatibility(for: "Hollow Knight")?.entries.count == 5)
    #expect(wiki.calls.count == 2)
    wiki.offline = false
    _ = await cache.compatibility(for: "Hollow Knight")
    #expect(wiki.calls.count == 3)
    // A page that isn't there is remembered too.
    #expect(await cache.compatibility(for: "Pocket Racer") == nil)
    #expect(await cache.compatibility(for: "Pocket Racer") == nil)
    #expect(wiki.calls.filter { $0 == "Pocket_Racer" }.count == 1)
}

// FIXLOG 2026-11-24: the site's "Page Not Found" web page isn't the wiki saying it has no page.
@Test func onlyTheWikisOwnNotFoundMeansNoPage() throws {
    let wikiText = Data("{{Compatibility/macOS}}".utf8)
    #expect(try AppleGamingWiki.source(status: 200, contentType: "text/x-wiki; charset=UTF-8", data: wikiText) == "{{Compatibility/macOS}}")
    #expect(try AppleGamingWiki.source(status: 404, contentType: "text/x-wiki; charset=UTF-8", data: Data()) == nil)
    #expect(throws: URLError.self) { try AppleGamingWiki.source(status: 404, contentType: "text/html; charset=utf-8", data: Data("<title>Page Not Found</title>".utf8)) }
    #expect(throws: URLError.self) { try AppleGamingWiki.source(status: 200, contentType: "text/html", data: Data("<html>".utf8)) }
    #expect(throws: URLError.self) { try AppleGamingWiki.source(status: 503, contentType: "text/x-wiki", data: Data()) }
}

@Test func noPageIsAskedAgainTheNextDay() async {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarAGW-\(UUID().uuidString)")
    let wiki = Wiki(), clock = Clock()
    let cache = CompatibilityCache(folder: folder, fetch: { try wiki.fetch($0) }, now: { clock.now })
    #expect(await cache.compatibility(for: "Pocket Racer") == nil)
    clock.now += 2 * 86400
    _ = await cache.compatibility(for: "Pocket Racer")
    #expect(wiki.calls.filter { $0 == "Pocket_Racer" }.count == 2)
}

@Test func theWikisSearchFindsTheSameNameWrittenDifferently() async {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarAGW-\(UUID().uuidString)")
    let wiki = Wiki()
    let cache = CompatibilityCache(folder: folder, fetch: { try wiki.fetch($0) },
                                   search: { query in query == "Hollow Knight™" ? ["Hollow Knight: Silksong", "Hollow Knight"] : ["Hollow Knight"] })
    #expect(await cache.compatibility(for: "Hollow Knight™")?.page == "Hollow_Knight")
    #expect(wiki.calls == ["Hollow_Knight™", "Hollow_Knight"])
    // Another game in the results isn't taken for this one.
    #expect(await cache.compatibility(for: "Hollow Knight Deluxe") == nil)
    #expect(AppleGamingWiki.sameGame("Baldur's Gate 3", "Baldurs Gate 3"))
    #expect(AppleGamingWiki.sameGame("DRAGON QUEST XI S: Echoes – Definitive Edition", "Dragon Quest XI S Echoes - Definitive Edition"))
    #expect(!AppleGamingWiki.sameGame("Diablo II Resurrected", "Diablo II"))
}

@Test func aRedirectIsFollowedOnce() async {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarAGW-\(UUID().uuidString)")
    let wiki = Wiki()
    let cache = CompatibilityCache(folder: folder, fetch: { try wiki.fetch($0) })
    _ = await cache.compatibility(for: "Bloodstained")
    #expect(wiki.calls == ["Bloodstained", "Bloodstained:_Ritual_of_the_Night"])
}
