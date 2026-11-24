import Foundation
import Testing
@testable import HangarKit

// S-036
@Test func readsEpicGOGAndSideloadedGamesFromHeroic() throws {
    let roots = try fixtureRoots()
    let games = HeroicScanner.scan(config: roots.heroic)
    #expect(games.map(\.title).sorted() == ["Ember Isles", "Lantern Road", "Paper Kites"])
    let ember = try #require(games.first { $0.title == "Ember Isles" })
    #expect(ember.id == "heroic:legendary:Ember")
    #expect(ember.source == .heroic && ember.runner == .heroic && ember.isWindows)
    #expect(ember.heroic?.store == "Epic")
    #expect(ember.path.hasSuffix("/Games/Ember Isles"))
    #expect(ember.processHints.contains("\\EmberIsles.exe"))
    let lantern = try #require(games.first { $0.heroic?.runner == "gog" })
    #expect(lantern.title == "Lantern Road")
    #expect(lantern.exe?.hasSuffix("/Games/Lantern Road/LanternRoad.exe") == true)
    #expect(games.first { $0.title == "Paper Kites" }?.heroic?.store == nil)
}

@Test func heroicGamesLaunchThroughHeroic() throws {
    let roots = try fixtureRoots()
    let ember = try #require(HeroicScanner.scan(config: roots.heroic).first { $0.title == "Ember Isles" })
    let plan = try LaunchPlanner.plan(for: ember, roots: roots)
    #expect(plan.executable.path == "/usr/bin/open")
    #expect(plan.arguments == ["heroic://launch?appName=Ember&runner=legendary"])
    var gone = roots
    gone.heroicApp = nil
    #expect(throws: LaunchError.heroicMissing) { try LaunchPlanner.plan(for: ember, roots: gone) }
}

@Test func noHeroicMeansNoGames() {
    #expect(HeroicScanner.scan(config: URL(fileURLWithPath: "/nonexistent/heroic")).isEmpty)
    let empty = FileManager.default.temporaryDirectory.appending(path: "HangarTests-heroic-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    #expect(HeroicScanner.scan(config: empty).isEmpty)
}

@Test func heroicKnowsEachGamesPrefix() throws {
    let roots = try fixtureRoots()
    #expect(HeroicScanner.prefix(config: roots.heroic, appName: "Ember")?.path.hasSuffix("/Heroic/Prefixes/Ember") == true)
    #expect(HeroicScanner.prefix(config: roots.heroic, appName: "kites01") == nil)
}

@Test func olderLibrariesOpenWithoutHeroicFields() throws {
    let json = #"{"games":[{"id":"steam:1","title":"Old","source":"steam"}]}"#
    let file = try JSONDecoder().decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.games.first?.heroic == nil)
}
