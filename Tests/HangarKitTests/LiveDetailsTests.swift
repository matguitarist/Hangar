import Foundation
import Testing
@testable import HangarKit

/// Against the real Steam store and TheGamesDB, only when asked:
///   HANGAR_LIVE_TGDB_KEY=<key> swift test --filter LiveDetails
private let liveKey = ProcessInfo.processInfo.environment["HANGAR_LIVE_TGDB_KEY"]

@Test(.enabled(if: liveKey != nil)) func liveDetailsFromSteamAndTheGamesDB() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "hangar-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = GameDetailsCache(folder: folder, key: liveKey)
    let steam = try #require(await cache.details(steamID: "367520", language: "french"))
    #expect(steam.developers == ["Team Cherry"])
    #expect(!steam.summary.isEmpty && !steam.genres.isEmpty)
    let tgdb = try #require(await cache.details(title: "Hollow Knight", mac: false))
    #expect(tgdb.source == .theGamesDB)
    #expect(tgdb.developers.contains("Team Cherry"))
    #expect(!tgdb.genres.isEmpty)
    let pcgw = GameDataCache(folder: folder.appending(path: "pcgw"))
    let data = try #require(await pcgw.data(for: "Hollow Knight"))
    #expect(data.entries(isWindows: false, onSteam: true).contains { $0.kind == .saves })
    print("LIVE pcgw:", data.entries.filter { $0.kind == .saves }.map(\.platform))
    print("LIVE steam:", steam.genres, steam.releaseText ?? "-", "| tgdb:", tgdb.developers, tgdb.publishers, tgdb.genres, tgdb.releaseDate.map { "\($0)" } ?? "-")
}
