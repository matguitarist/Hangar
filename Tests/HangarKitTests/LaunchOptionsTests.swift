import Foundation
import Testing
@testable import HangarKit

// S-012
@Test func theMetalHUDReachesEveryKindOfLaunch() throws {
    let roots = try fixtureRoots()
    let fm = FileManager.default
    // A CrossOver with a wine command, so bottle games can plan a launch.
    let wine = roots.crossOverApp!.appending(path: "Contents/SharedSupport/CrossOver/bin/wine")
    try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: wine.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    let games = LibraryScanner.scanNow(roots)
    for title in ["Starfall Arcade", "Vernal Edge", "Moonlit Harbor", "Hollow Knight"] {
        var game = try #require(games.first { $0.title == title })
        #expect(try LaunchPlanner.plan(for: game, roots: roots).environment["MTL_HUD_ENABLED"] == nil)
        game.options.metalHUD = true
        #expect(try LaunchPlanner.plan(for: game, roots: roots).environment["MTL_HUD_ENABLED"] == "1", "\(title)")
    }
}

@Test func aNativeSteamGameWithTheHUDOpensItsOwnApp() throws {
    let roots = try fixtureRoots()
    var knight = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Hollow Knight" })
    #expect(try LaunchPlanner.plan(for: knight, roots: roots).arguments == ["steam://rungameid/367520"])
    knight.options.metalHUD = true
    #expect(try LaunchPlanner.plan(for: knight, roots: roots).arguments.first?.hasSuffix("Hollow Knight/hollow_knight.app") == true)
}

@Test func olderOptionsStillOpen() throws {
    let options = try JSONDecoder().decode(GameOptions.self, from: Data("{}".utf8))
    #expect(options == GameOptions())
}

// S-013
@Test func argumentsWithSpacesAndQuotesSplitAsTyped() {
    #expect(ShellWords.split(#"-windowed -name "Big Map" -path 'C:\Games\X' a\ b"#) == ["-windowed", "-name", "Big Map", "-path", #"C:\Games\X"#, "a b"])
    #expect(ShellWords.split("  ") == [])
    #expect(ShellWords.split(#"-title "" -x"#) == ["-title", "", "-x"])
    #expect(ShellWords.split(#"say "it's here""#) == ["say", "it's here"])
}

@Test func launchOptionsReachEveryKindOfLaunch() throws {
    let roots = try fixtureRoots()
    let fm = FileManager.default
    let wine = roots.crossOverApp!.appending(path: "Contents/SharedSupport/CrossOver/bin/wine")
    try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: wine.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    let games = LibraryScanner.scanNow(roots)
    let options = GameOptions(arguments: #"-windowed -name "Big Map""#, variables: [EnvironmentVariable(name: "DXVK_HUD", value: "fps"),
                                                                              EnvironmentVariable(name: " ", value: "ignored")])
    var starfall = try #require(games.first { $0.title == "Starfall Arcade" })
    starfall.options = options
    let mac = try LaunchPlanner.plan(for: starfall, roots: roots)
    #expect(mac.appArguments == ["-windowed", "-name", "Big Map"] && mac.environment == ["DXVK_HUD": "fps"])

    var vernal = try #require(games.first { $0.title == "Vernal Edge" })
    vernal.options = options
    #expect(try LaunchPlanner.plan(for: vernal, roots: roots).arguments.suffix(5) == ["-applaunch", "1546710", "-windowed", "-name", "Big Map"])

    var harbor = try #require(games.first { $0.title == "Moonlit Harbor" })
    harbor.options = options
    harbor.options.exe = "C:/Program Files/Moonlit Harbor/Launcher.exe"
    let plan = try LaunchPlanner.plan(for: harbor, roots: roots)
    #expect(plan.arguments == ["--bottle", "Classics", "--no-wait", "--cx-app", "C:/Program Files/Moonlit Harbor/Launcher.exe", "-windowed", "-name", "Big Map"])
    #expect(plan.processHints.contains("Launcher.exe"))
}

@Test func aSavedLibraryKeepsLaunchOptions() throws {
    var game = Game(id: "x", title: "X", source: .addedByHand)
    game.options = GameOptions(metalHUD: true, arguments: "-a", variables: [EnvironmentVariable(name: "A", value: "1")], exe: "C:/x.exe")
    let data = try JSONEncoder().encode(game)
    #expect(try JSONDecoder().decode(Game.self, from: data).options == game.options)
}
