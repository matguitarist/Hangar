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
