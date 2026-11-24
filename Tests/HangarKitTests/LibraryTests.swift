import Foundation
import Testing
@testable import HangarKit

/// The sample library in Tests/Fixtures, copied to a fresh temporary folder.
func fixtureRoots(_ name: String = #function) throws -> LibraryRoots {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures")
    let target = FileManager.default.temporaryDirectory.appending(path: "HangarTests-\(UUID().uuidString)")
    return try FixtureLibrary.install(from: source, to: target)
}

// S-001
@Test func readsEverySteamLibraryAndSkipsMissingOnes() throws {
    let roots = try fixtureRoots()
    let result = SteamScanner.scan(steamRoot: roots.steam)
    #expect(Set(result.games.map(\.title)) == ["Hollow Knight", "Stardew Valley", "Baldur's Gate 3"])
    #expect(result.notes == [.libraryMissing(path: "/Volumes/HangarFixtureDrive/SteamLibrary")])
    let knight = try #require(result.games.first { $0.steamID == "367520" })
    #expect(knight.id == "steam:367520")
    #expect(knight.path.hasSuffix("/Steam/steamapps/common/Hollow Knight"))
}

@Test func keyValuesReadsNestedBlocksAndEscapes() {
    let vdf = KeyValues.parse(#""a" { "path" "C:\\Games" "apps" { "1" "2" } } // comment"#)
    #expect(vdf["a"]?["path"]?.string == #"C:\Games"#)
    #expect(vdf["A"]?["apps"]?["1"]?.string == "2")
}

@Test func gamesOnAnUnpluggedDriveStayInTheLibrary() {
    var file = LibraryFile(games: [Game(id: "steam:1", title: "Far", source: .steam, path: "/Volumes/Data/SteamLibrary/steamapps/common/Far"),
                                   Game(id: "app:/x", title: "Gone", source: .macApp, path: "/Applications/Gone.app")])
    file.games[0].playtime = 600
    file.merge(scanned: [], unreachable: ["/Volumes/Data/SteamLibrary"])
    #expect(file.games.map(\.id) == ["steam:1"])
    #expect(file.games[0].playtime == 600)
}

// S-002
@Test func readsTheBottleFolderFromCrossOversPreferences() {
    let home = URL(fileURLWithPath: "/Users/someone")
    #expect(CrossOverScanner.bottleFolder(preferences: ["BottleDir": "/Volumes/Games/Bottles"], home: home).path == "/Volumes/Games/Bottles")
    #expect(CrossOverScanner.bottleFolder(preferences: nil, home: home).path == "/Users/someone/Library/Application Support/CrossOver/Bottles")
}

@Test func findsSteamGamesAndProgramsInBottles() throws {
    let roots = try fixtureRoots()
    let result = CrossOverScanner.scan(bottles: roots.bottles)
    #expect(result.bottles == ["Classics", "Empty", "Steam"])
    #expect(Set(result.games.map(\.title)) == ["Vernal Edge", "Kynseed", "Bloodstained: Ritual of the Night", "Moonlit Harbor"])
    let vernal = try #require(result.games.first { $0.title == "Vernal Edge" })
    #expect(vernal.bottle == "Steam" && vernal.steamID == "1546710" && vernal.runner == .crossOver)
    let harbor = try #require(result.games.first { $0.title == "Moonlit Harbor" })
    #expect(harbor.exe == "C:/ProgramData/Microsoft/Windows/Start Menu/Programs/Moonlit Harbor/Moonlit Harbor.lnk")
    #expect(harbor.startsShortcut && harbor.processHints.contains("\\moonlitharbor.exe"))
    #expect(result.notes == [.bottleUnreadable(name: "Empty")])
}

@Test func mapsWindowsPathsIntoTheBottle() {
    let bottle = URL(fileURLWithPath: "/B/Steam")
    #expect(CrossOverScanner.macPath(#"C:\Program Files (x86)\Steam"#, bottle: bottle)?.path == "/B/Steam/drive_c/Program Files (x86)/Steam")
}

// S-003
@Test func onlyAppsInAGamesCategoryCount() throws {
    let roots = try fixtureRoots()
    let games = MacAppScanner.scan(folders: roots.appFolders, excluding: nil)
    #expect(Set(games.map(\.title)) == ["Starfall Arcade", "Pocket Racer", "Tiny Tactics"])
    #expect(MacAppScanner.isGame(category: "public.app-category.role-playing-games"))
    #expect(!MacAppScanner.isGame(category: "public.app-category.finance"))
}

// S-004
@Test func addingTheSamePathTwiceKeepsOneGame() {
    var file = LibraryFile()
    let first = file.add(Game(id: "hand:/a.app", title: "A", source: .addedByHand, path: "/a.app"))
    let second = file.add(Game(id: "hand:/a.app-2", title: "A", source: .addedByHand, path: "/a.app"))
    #expect(file.games.count == 1 && first.id == second.id)
}

@Test func aRemovedGameStaysOutUntilRestored() {
    var file = LibraryFile()
    let game = Game(id: "app:/x.app", title: "X", source: .macApp, path: "/x.app")
    file.merge(scanned: [game])
    file.remove(id: game.id)
    file.merge(scanned: [game])
    #expect(file.games.isEmpty && file.removed.map(\.id) == [game.id])
    file.restore(id: game.id)
    #expect(file.games.map(\.id) == [game.id] && file.removed.isEmpty)
}

@Test func aScanKeepsPlaytimeAndAddedGames() {
    var file = LibraryFile()
    var game = Game(id: "steam:1", title: "A", source: .steam)
    file.merge(scanned: [game])
    file.games[0].playtime = 120
    file.add(Game(id: "hand:/b.app", title: "B", source: .addedByHand, path: "/b.app"))
    game.title = "A Renamed"
    file.merge(scanned: [game])
    #expect(file.games.map(\.title) == ["A Renamed", "B"])
    #expect(file.games[0].playtime == 120)
}

@Test func anOlderLibraryFileStillOpens() throws {
    let json = #"{"games":[{"id":"steam:1","title":"Old","source":"steam"}]}"#
    let file = try JSONDecoder().decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.games[0].runner == .native && file.games[0].playtime == 0 && file.collections.isEmpty)
}

// S-005
actor FetchCounter {
    var count = 0
    var online = true
    func hit() throws -> Data {
        count += 1
        guard online else { throw URLError(.notConnectedToInternet) }
        return Data(repeating: 7, count: 4096)
    }
    func goOffline() { online = false }
}

@Test func steamArtIsFetchedOnceAndCached() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarCovers-\(UUID().uuidString)")
    let counter = FetchCounter()
    let cache = CoverCache(folder: folder) { _ in try await counter.hit() }
    let first = await cache.cover(steamID: "367520")
    #expect(first != nil)
    await counter.goOffline()
    let again = await cache.cover(steamID: "367520")
    #expect(again == first)
    #expect(await counter.count == 1)
    // Offline with nothing cached: no file, so the generated cover shows; asked once per URL only.
    #expect(await cache.cover(steamID: "1") == nil)
    #expect(await cache.cover(steamID: "1") == nil)
    #expect(await counter.count == 1 + CoverCache.steamURLs("1").count)
    #expect(CoverCache.steamURLs("367520")[0].absoluteString.contains("/367520/library_600x900"))
}

// S-006
@Test func aBottleSteamGameLaunchesThroughTheBottlesSteam() throws {
    var roots = try fixtureRoots()
    let fakeApp = FileManager.default.temporaryDirectory.appending(path: "HangarCX-\(UUID().uuidString)/CrossOver.app")
    let wine = fakeApp.appending(path: "Contents/SharedSupport/CrossOver/bin/wine")
    try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: wine, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    roots.crossOverApp = fakeApp
    let games = CrossOverScanner.scan(bottles: roots.bottles).games
    let vernal = try #require(games.first { $0.title == "Vernal Edge" })
    let plan = try LaunchPlanner.plan(for: vernal, roots: roots)
    #expect(plan.executable == wine)
    #expect(plan.arguments == ["--bottle", "Steam", "--no-wait", "--cx-app", "C:/Program Files (x86)/Steam/steam.exe", "-silent", "-applaunch", "1546710"])
    let byHand = Game(id: "hand:x", title: "Moonlit Harbor", source: .addedByHand, runner: .crossOver,
                      path: "/x/MoonlitHarbor.exe", exe: "C:/Program Files/Moonlit Harbor/MoonlitHarbor.exe", bottle: "Classics")
    #expect(try LaunchPlanner.plan(for: byHand, roots: roots).arguments == ["--bottle", "Classics", "--no-wait", "--cx-app", "C:/Program Files/Moonlit Harbor/MoonlitHarbor.exe"])
    roots.crossOverApp = nil
    #expect(throws: LaunchError.crossOverMissing) { try LaunchPlanner.plan(for: vernal, roots: roots) }
}

@Test func runningFollowsTheGamesOwnProcess() {
    let hints = ["steamapps\\common\\Vernal Edge\\", "steamapps/common/Vernal Edge/"]
    let processes = [
        RunningProcess(pid: 10, path: "/usr/bin/perl", arguments: ["wine", "--bottle", "Steam", "--cx-app", "steam.exe", "-applaunch", "1546710"]),
        RunningProcess(pid: 11, path: "/x/wine64-preloader", arguments: [#"C:\Program Files (x86)\Steam\steam.exe"#]),
        RunningProcess(pid: 12, path: "/x/wine64-preloader", arguments: [#"C:\Program Files (x86)\Steam\steamapps\common\Vernal Edge\VernalEdge.exe"#]),
    ]
    #expect(ProcessList.find(hints, in: processes).map(\.pid) == [12])
    #expect(ProcessList.find([], in: processes).isEmpty)
}

@Test func readsWhetherTheBottlesSteamIsSignedIn() throws {
    let roots = try fixtureRoots()
    let steam = CrossOverScanner.steamFolder(bottle: roots.bottles.appending(path: "Steam"))
    #expect(SteamScanner.isSignedIn(steamRoot: steam))
    try FileManager.default.removeItem(at: steam.appending(path: "config/loginusers.vdf"))
    #expect(!SteamScanner.isSignedIn(steamRoot: steam))
}

// S-008
@Test func searchFindsWordsInAnyOrderAndInitials() {
    #expect(GameSearch.matches("bg3", title: "Baldur's Gate 3"))
    #expect(GameSearch.matches("knight hollow", title: "Hollow Knight"))
    #expect(GameSearch.matches("baldurs", title: "Baldur's Gate 3"))
    #expect(GameSearch.matches("pokemon", title: "Pokémon"))
    #expect(!GameSearch.matches("knight xyz", title: "Hollow Knight"))
}

@Test func sortsByRecentlyPlayedAndPlaytime() {
    var a = Game(id: "a", title: "Alpha", source: .steam)
    var b = Game(id: "b", title: "Beta", source: .steam)
    let c = Game(id: "c", title: "Gamma", source: .steam)
    a.lastPlayed = Date(timeIntervalSince1970: 100); b.lastPlayed = Date(timeIntervalSince1970: 200)
    a.playtime = 50; b.playtime = 10
    #expect(GameSort.recentlyPlayed.sorted([c, a, b]).map(\.id) == ["b", "a", "c"])
    #expect(GameSort.playtime.sorted([c, b, a]).map(\.id) == ["a", "b", "c"])
    #expect(PlaytimeText.short(3 * 3600 + 20 * 60) == "3 h 20 min")
}

@Test func aTrackedGameStartsRunsAndFinishes() {
    let t0 = Date(timeIntervalSince1970: 1000)
    let hints = ["/Games/Starfall.app/"]
    let game = RunningProcess(pid: 42, path: "/Games/Starfall.app/Contents/MacOS/Starfall", arguments: [])
    var state = LaunchState(launched: t0)
    #expect(LaunchTracker.step(&state, hints: hints, processes: [], now: t0.addingTimeInterval(2)) == nil)
    #expect(LaunchTracker.step(&state, hints: hints, processes: [game], now: t0.addingTimeInterval(3)) == .started)
    #expect(state.phase == .running && state.pids == [42])
    #expect(LaunchTracker.step(&state, hints: hints, processes: [game], now: t0.addingTimeInterval(60)) == nil)
    #expect(LaunchTracker.step(&state, hints: hints, processes: [], now: t0.addingTimeInterval(603)) == .finished(played: 600, quitRightAway: false))
}

@Test func aGameThatQuitsUnderTenSecondsQuitRightAwayUnlessStopped() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var state = LaunchState(launched: t0)
    #expect(LaunchTracker.launched(&state, pid: 7, now: t0) == .started)
    #expect(LaunchTracker.step(&state, hints: [], processes: [], now: t0.addingTimeInterval(4)) == .finished(played: 4, quitRightAway: true))
    var stopped = LaunchState(launched: t0)
    _ = LaunchTracker.launched(&stopped, pid: 7, now: t0)
    stopped.stoppedByUser = true
    #expect(LaunchTracker.step(&stopped, hints: [], processes: [], now: t0.addingTimeInterval(4)) == .finished(played: 4, quitRightAway: false))
}

@Test func aGameWhoseProcessNeverAppearsDidntStart() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var native = LaunchState(launched: t0)
    #expect(LaunchTracker.step(&native, hints: ["x"], processes: [], now: t0.addingTimeInterval(31)) == .didntStart)
    var steam = LaunchState(launched: t0, slowStart: true)
    #expect(LaunchTracker.step(&steam, hints: ["x"], processes: [], now: t0.addingTimeInterval(31)) == nil)
    #expect(LaunchTracker.step(&steam, hints: ["x"], processes: [], now: t0.addingTimeInterval(121)) == .didntStart)
}
