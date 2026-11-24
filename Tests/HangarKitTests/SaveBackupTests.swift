import Foundation
import Testing
@testable import HangarKit

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "hangar-backups-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// S-022
@Test func keepsTenBackupsAndRemovesOlderOnes() throws {
    let dir = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let saves = dir.appending(path: "Saves")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    let store = SaveBackupStore(root: dir.appending(path: "Backups"))
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for n in 0..<12 {
        try Data("save \(n)".utf8).write(to: saves.appending(path: "slot.sav"))
        #expect(try store.backUp("steam:1", saves: [saves], reason: .launch, now: start.addingTimeInterval(Double(n) * 60)) != nil)
    }
    let list = store.list("steam:1")
    #expect(list.count == 10)
    #expect(list.first?.date == start.addingTimeInterval(11 * 60))
    #expect(list.last?.date == start.addingTimeInterval(2 * 60))
    #expect(list.first?.files == 1 && list.first?.bytes == 7)
}

@Test func skipsACopyWhenNothingChanged() throws {
    let dir = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "user1.dat")
    try Data("one".utf8).write(to: file)
    let store = SaveBackupStore(root: dir.appending(path: "Backups"))
    #expect(try store.backUp("g", saves: [file], reason: .launch) != nil)
    #expect(try store.backUp("g", saves: [file], reason: .launch) == nil)
    try Data("two!".utf8).write(to: file)
    #expect(try store.backUp("g", saves: [file], reason: .launch) != nil)
    #expect(store.list("g").count == 2)
    // Nothing saved yet: nothing to copy.
    #expect(try store.backUp("h", saves: [dir.appending(path: "missing")], reason: .launch) == nil)
}

// S-023
@Test func restorePutsTheOldSaveBack() throws {
    let dir = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let saves = dir.appending(path: "Saves")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: saves.appending(path: "slot.sav"))
    let store = SaveBackupStore(root: dir.appending(path: "Backups"))
    let old = try #require(try store.backUp("g", saves: [saves], reason: .launch))
    try Data("new".utf8).write(to: saves.appending(path: "slot.sav"))
    try Data("extra".utf8).write(to: saves.appending(path: "extra.sav"))
    try store.restore(old, gameID: "g")
    #expect(try String(contentsOf: saves.appending(path: "slot.sav"), encoding: .utf8) == "old")
    #expect(!FileManager.default.fileExists(atPath: saves.appending(path: "extra.sav").path))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".hangar-restore") }
    #expect(leftovers.isEmpty)
}

@Test func backupsMoveToAnotherFolder() throws {
    let dir = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "user1.dat")
    try Data("one".utf8).write(to: file)
    let local = SaveBackupStore(root: dir.appending(path: "Local"))
    let cloud = SaveBackupStore(root: dir.appending(path: "Cloud"))
    try local.backUp("g", saves: [file], reason: .launch)
    try local.move(to: cloud)
    #expect(local.list("g").isEmpty)
    #expect(cloud.list("g").count == 1)
}
