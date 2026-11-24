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

@Test func aRedirectIsFollowedOnce() async {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarAGW-\(UUID().uuidString)")
    let wiki = Wiki()
    let cache = CompatibilityCache(folder: folder, fetch: { try wiki.fetch($0) })
    _ = await cache.compatibility(for: "Bloodstained")
    #expect(wiki.calls == ["Bloodstained", "Bloodstained:_Ritual_of_the_Night"])
}
