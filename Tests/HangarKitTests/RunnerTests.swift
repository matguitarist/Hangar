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

// S-014
@Test func aWineBuildRunsAProgramInAPrefixOfItsOwn() throws {
    let roots = try fixtureRoots()
    let runners = RunnerScanner.scan(roots)
    var harbor = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Moonlit Harbor" })
    let wine = try #require(runners.first { $0.kind == .wine })
    harbor.options.runner = wine.path
    harbor.options.arguments = "-windowed"
    let plan = try LaunchPlanner.plan(for: harbor, roots: roots)
    #expect(plan.executable.path == wine.wine)
    #expect(plan.arguments == ["start", "/unix", harbor.path, "-windowed"])
    #expect(plan.environment["WINEPREFIX"]?.hasPrefix(roots.prefixes.path + "/Moonlit Harbor-") == true)
    #expect(plan.environment["WINEDEBUG"] == "-all")

    // An exe chosen on the Settings tab runs directly, from its own folder.
    harbor.options.exe = "C:/Program Files/Moonlit Harbor/MoonlitHarbor.exe"
    let gptk = try #require(runners.first { $0.kind == .gamePortingToolkit })
    harbor.options.runner = gptk.path
    let exe = try LaunchPlanner.plan(for: harbor, roots: roots)
    #expect(exe.executable.path.hasSuffix("Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"))
    #expect(exe.arguments.first?.hasSuffix("drive_c/Program Files/Moonlit Harbor/MoonlitHarbor.exe") == true)
    #expect(exe.workingDirectory?.lastPathComponent == "Moonlit Harbor")
    #expect(exe.environment["WINEPREFIX"] == plan.environment["WINEPREFIX"])
}

@Test func aRunnerThatIsGoneSaysSo() throws {
    let roots = try fixtureRoots()
    var harbor = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Moonlit Harbor" })
    harbor.options.runner = "/Applications/Wine Gone.app"
    #expect(throws: LaunchError.runnerMissing) { try LaunchPlanner.plan(for: harbor, roots: roots) }
}

@Test func steamGamesInABottleKeepCrossOver() throws {
    let roots = try fixtureRoots()
    var vernal = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Vernal Edge" })
    vernal.options.runner = RunnerScanner.scan(roots).first { $0.kind == .wine }?.path
    #expect(throws: LaunchError.crossOverMissing) { try LaunchPlanner.plan(for: vernal, roots: roots) }
}
