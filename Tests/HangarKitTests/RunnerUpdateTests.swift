import Foundation
import Testing
@testable import HangarKit

// S-018
@Test func aRunnerVersionChangeIsNoticed() throws {
    let roots = try fixtureRoots()
    let runners = RunnerScanner.scan(roots)
    let crossOver = try #require(runners.first { $0.kind == .crossOver })
    #expect(crossOver.version == "26.3")
    let file = FileManager.default.temporaryDirectory.appending(path: "HangarRunners-\(UUID().uuidString).json")

    // First look: nothing to compare with.
    #expect(RunnerVersions.changes(previous: RunnerVersions.load(file), current: runners).isEmpty)
    try RunnerVersions.save(runners, to: file)
    #expect(RunnerVersions.changes(previous: RunnerVersions.load(file), current: runners).isEmpty)

    var previous = RunnerVersions.load(file)
    previous[crossOver.path] = "26.2"
    let changes = RunnerVersions.changes(previous: previous, current: runners)
    #expect(changes == [RunnerUpdate(name: "CrossOver", path: crossOver.path, old: "26.2", new: "26.3")])
    #expect(changes.first?.oldLabel == "CrossOver 26.2")
}

@Test func theGamesThatLastWorkedOnTheOldVersionAreListed() throws {
    let store = SnapshotStore(folder: FileManager.default.temporaryDirectory.appending(path: "HangarRU-\(UUID().uuidString)"))
    var old = Game(id: "old", title: "Old", source: .macApp)
    let other = Game(id: "other", title: "Other", source: .macApp)
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let worked = try store.take(old, bottle: nil, reason: .launch, runner: "CrossOver 26.2", now: t)
    try store.markWorked(worked, on: t)
    // A newer snapshot that didn't work doesn't hide the one that did.
    old.options.arguments = "-x"
    try store.take(old, bottle: nil, reason: .settings, runner: "CrossOver 26.3", now: t + 10)
    let elsewhere = try store.take(other, bottle: nil, reason: .launch, runner: "CrossOver 26.1", now: t)
    try store.markWorked(elsewhere, on: t)

    let update = RunnerUpdate(name: "CrossOver", path: "/Applications/CrossOver.app", old: "26.2", new: "26.3")
    let listed = RunnerVersions.lastWorked(on: update, gameIDs: ["old", "other", "none"], store: store)
    #expect(listed.map(\.gameID) == ["old"] && listed.first?.id == worked.id)
}
