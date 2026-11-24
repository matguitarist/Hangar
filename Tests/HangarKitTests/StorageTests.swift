import Foundation
import Testing
@testable import HangarKit

// S-039
@Test func storageCountsEachBottleOnceAndMarksUnusedPrefixes() async throws {
    let roots = try fixtureRoots()
    let games = LibraryScanner.scanNow(roots)
    let used = roots.prefixes.appending(path: "Used")
    let unused = roots.prefixes.appending(path: "Old")
    for folder in [used, unused] {
        try FileManager.default.createDirectory(at: folder.appending(path: "drive_c"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50_000).write(to: folder.appending(path: "drive_c/file.bin"))
    }
    let snapshots = roots.prefixes.deletingLastPathComponent().appending(path: "Snapshots")
    let input = StorageScanner.Input(games: games, bottles: roots.bottles, bottleNames: ["Classics", "Steam"], prefixes: roots.prefixes,
                                     usedPrefixes: [used.standardizedFileURL.path], snapshots: snapshots, saveBackups: snapshots)
    let items = await StorageScanner.measure(input)
    #expect(items.filter { $0.kind == .bottles }.map(\.name).sorted() == ["Classics", "Steam"])
    // Vernal Edge lives in the bottle Steam: it isn't counted again as a game.
    #expect(!items.contains { $0.kind == .games && $0.name == "Vernal Edge" })
    #expect(items.contains { $0.kind == .games && $0.name == "Hollow Knight" })
    #expect(items.first { $0.name == "Old" }?.unused == true)
    #expect(items.first { $0.name == "Used" }?.unused == false)
    #expect(items.first { $0.name == "Old" }.map { $0.bytes >= 50_000 } == true)
    #expect(zip(items, items.dropFirst()).allSatisfy { $0.bytes >= $1.bytes })
    let totals = StorageScanner.totals(items)
    #expect(totals[.prefixes] == items.filter { $0.kind == .prefixes }.map(\.bytes).reduce(0, +))
}

@Test func deleteOldSnapshotsKeepsTheNewestAndTheWorkingOnes() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarTests-snapshots-\(UUID().uuidString)")
    let store = SnapshotStore(folder: folder)
    var game = Game(id: "g", title: "G", source: .macApp)
    var worked: SettingsSnapshot?
    for n in 0..<6 {
        game.options.arguments = "-n \(n)"
        let s = try store.take(game, bottle: nil, reason: .settings)
        if n == 0 { worked = s }
    }
    try store.markWorked(try #require(worked))
    #expect(store.list("g").count == 6)
    #expect(store.deleteOld(gameIDs: ["g"], keep: 3) == 2)
    let left = store.list("g")
    #expect(left.count == 4 && left.contains { $0.worked != nil })
}
