import Foundation
import Testing
@testable import HangarKit

private func store() -> SnapshotStore {
    SnapshotStore(folder: FileManager.default.temporaryDirectory.appending(path: "HangarSnapshots-\(UUID().uuidString)"))
}

// S-017
@Test func aSnapshotPutsTheBottleFilesBackByteForByte() throws {
    let roots = try fixtureRoots()
    let bottle = roots.bottles.appending(path: "Steam")
    var game = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Vernal Edge" })
    game.options.metalHUD = true
    let snapshots = store()
    let before = try SnapshotStore.bottleFiles.map { try? Data(contentsOf: bottle.appending(path: $0)) }
    let dll = "drive_c/Program Files (x86)/Steam/steamapps/common/Vernal Edge/dxgi.dll"
    let snapshot = try snapshots.take(game, bottle: bottle, extraFiles: [dll], reason: .settings, runner: "CrossOver 26.3")
    #expect(snapshot.files.map(\.path).contains("cxbottle.conf"))
    #expect(snapshot.files.first { $0.path == dll }?.existed == false)

    // Break things: other settings, a changed registry, a DLL that wasn't there.
    try BottleSettings(graphics: .wined3d, msync: false, highResolution: true).write(bottle: bottle)
    try Data("garbage".utf8).write(to: bottle.appending(path: "system.reg"))
    try FileManager.default.createDirectory(at: bottle.appending(path: dll).deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("MZ".utf8).write(to: bottle.appending(path: dll))

    let options = try snapshots.restore(snapshot, bottle: bottle)
    #expect(options.metalHUD)
    let after = try SnapshotStore.bottleFiles.map { try? Data(contentsOf: bottle.appending(path: $0)) }
    #expect(after == before)
    #expect(!FileManager.default.fileExists(atPath: bottle.appending(path: dll).path))
}

@Test func anUnchangedGameDoesntPileUpSnapshots() throws {
    let roots = try fixtureRoots()
    let bottle = roots.bottles.appending(path: "Steam")
    let game = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Vernal Edge" })
    let snapshots = store()
    let first = try snapshots.take(game, bottle: bottle, reason: .launch)
    let again = try snapshots.take(game, bottle: bottle, reason: .launch)
    #expect(first.id == again.id && snapshots.list(game.id).count == 1)
    try BottleSettings(graphics: .dxvk).write(bottle: bottle)
    _ = try snapshots.take(game, bottle: bottle, reason: .settings)
    #expect(snapshots.list(game.id).count == 2)
    #expect(snapshots.list(game.id).first?.reason == .settings)
}

@Test func snapshotsInTheSameSecondKeepTheirOrder() throws {
    let snapshots = store()
    var game = Game(id: "app:/y", title: "Y", source: .macApp)
    let now = Date(timeIntervalSince1970: 1_800_000_000.25)
    try snapshots.take(game, bottle: nil, reason: .settings, now: now)
    game.options.arguments = "-b"
    try snapshots.take(game, bottle: nil, reason: .restore, now: now + 0.5)
    #expect(snapshots.list(game.id).map(\.reason) == [.restore, .settings])
}

@Test func markingWorkedLabelsTheSnapshotAndKeepsItWhenOldOnesGo() throws {
    let snapshots = store()
    var game = Game(id: "app:/x", title: "X", source: .macApp)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let first = try snapshots.take(game, bottle: nil, reason: .launch, now: start)
    try snapshots.markWorked(first, on: start)
    for i in 1...(SnapshotStore.keep + 3) {
        game.options.arguments = "-\(i)"
        try snapshots.take(game, bottle: nil, reason: .launch, now: start + Double(i))
    }
    let all = snapshots.list(game.id)
    #expect(all.count == SnapshotStore.keep + 1)
    #expect(all.last?.id == first.id && all.last?.worked == start)
}
