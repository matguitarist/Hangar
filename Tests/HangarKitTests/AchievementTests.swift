import Foundation
import Testing
@testable import HangarKit

// S-041
@Test func achievementsComeFromSteamsStatsFiles() throws {
    let roots = try fixtureRoots()
    let summary = try #require(SteamAchievements.read(steamRoot: roots.steam, appID: "367520"))
    #expect(summary.total == 40)
    #expect(summary.unlocked == 12)
    #expect(summary.recent.map(\.name) == ["Achievement 34", "Achievement 33", "Achievement 10"])
    let french = try #require(SteamAchievements.read(steamRoot: roots.steam, appID: "367520", language: SteamAchievements.language(for: "fr")))
    #expect(french.recent.last?.name == "Archiviste")
}

@Test func noSchemaOrABrokenFileMeansNoAchievements() throws {
    let roots = try fixtureRoots()
    #expect(SteamAchievements.read(steamRoot: roots.steam, appID: "413150") == nil)
    #expect(BinaryKeyValues.parse(Data([0x05, 0x41, 0x00])) == nil)
}

@Test func withoutAUserFileNothingIsUnlocked() throws {
    let roots = try fixtureRoots()
    let stats = roots.steam.appending(path: "appcache/stats")
    try FileManager.default.removeItem(at: stats.appending(path: "UserGameStats_10001_367520.bin"))
    let summary = try #require(SteamAchievements.read(steamRoot: roots.steam, appID: "367520"))
    #expect(summary.total == 40 && summary.unlocked == 0 && summary.recent.isEmpty)
}
