import Foundation
import Testing
@testable import HangarKit

// S-009
@Test func findsCrossOverWineBuildsAndGamePortingToolkit() throws {
    let roots = try fixtureRoots()
    let runners = RunnerScanner.scan(roots)
    #expect(runners.map(\.name) == ["CrossOver", "Wine Stable", "Game Porting Toolkit"])
    #expect(runners.map(\.version) == ["26.3", "10.0", "3.0"])
    #expect(runners[1].kind == .wine && runners[1].wine?.hasSuffix("Wine Stable.app/Contents/Resources/wine/bin/wine") == true)
    #expect(runners[2].kind == .gamePortingToolkit && runners[2].wine?.hasSuffix("/wine64") == true)
    #expect(runners[1].runsPrefixes && !runners[0].runsPrefixes)
}

@Test func findsMacRunnerAndHomebrewsGamePortingToolkit() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "HangarRunners-\(UUID().uuidString)")
    let apps = root.appending(path: "Applications")
    try fm.createDirectory(at: apps.appending(path: "MacRunner.app/Contents"), withIntermediateDirectories: true)
    let keg = root.appending(path: "Cellar/game-porting-toolkit/1.1/bin")
    try fm.createDirectory(at: keg, withIntermediateDirectories: true)
    fm.createFile(atPath: keg.appending(path: "wine64").path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    try fm.createDirectory(at: root.appending(path: "opt"), withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: root.appending(path: "opt/game-porting-toolkit"), withDestinationURL: keg.deletingLastPathComponent())
    let roots = LibraryRoots(steam: root, bottles: root, crossOverApp: nil, appFolders: [apps], toolFolders: [root.appending(path: "opt")])
    let runners = RunnerScanner.scan(roots)
    #expect(runners.map(\.kind) == [.macRunner, .gamePortingToolkit])
    #expect(runners[1].version == "1.1")
}

@Test func withoutCrossOverThereIsNoCrossOverRunner() throws {
    var roots = try fixtureRoots()
    roots.crossOverApp = nil
    #expect(!RunnerScanner.scan(roots).contains { $0.kind == .crossOver })
}
