import Foundation
import Testing
@testable import HangarKit

// S-040
@Test func settingChangesUseTheSettingsTabWords() {
    let changes = BottleSettings.changes(from: BottleSettings(graphics: .d3dMetal, msync: true), to: BottleSettings(graphics: .auto, msync: true, avx: true))
    #expect(changes.map(\.name) == ["Graphics", "AVX for Rosetta"])
    #expect(changes.first?.old == "D3DMetal" && changes.first?.new == "Auto")
}

@Test func aBottleChangedAfterItsLastSnapshotIsListed() throws {
    let roots = try fixtureRoots()
    let games = LibraryScanner.scanNow(roots)
    let game = try #require(games.first { $0.bottle == "Classics" })
    let bottle = roots.bottles.appending(path: "Classics")
    let store = SnapshotStore(folder: FileManager.default.temporaryDirectory.appending(path: "HangarTests-drift-\(UUID().uuidString)"))
    _ = try BottleSettings(graphics: .d3dMetal, msync: true).write(bottle: bottle)
    _ = try store.take(game, bottle: bottle, reason: .launch)
    let map = ["Classics": [game.id]]
    #expect(RunnerVersions.drifts(bottles: map, bottleURL: { roots.bottles.appending(path: $0) }, store: store).isEmpty)
    // The update resets the backend.
    _ = try BottleSettings(graphics: .auto, msync: true).write(bottle: bottle)
    let drifts = RunnerVersions.drifts(bottles: map, bottleURL: { roots.bottles.appending(path: $0) }, store: store)
    #expect(drifts.map(\.bottle) == ["Classics"])
    #expect(drifts.first?.changes == [BottleSettingChange(name: "Graphics", old: "D3DMetal", new: "Auto")])
}
