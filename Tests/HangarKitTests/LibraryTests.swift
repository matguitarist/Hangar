import FileKit
import Foundation
import SteamKit
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

/// A manifest left in two libraries (a game moved between drives) gives one game, from the first library.
@Test func aGameInTwoLibrariesIsListedOnce() throws {
    let roots = try fixtureRoots()
    let drive = roots.steam.deletingLastPathComponent().appending(path: "Drive/SteamLibrary")
    let fixture = try SteamFixture(root: roots.steam)
    try fixture.addLibrary(drive)
    try fixture.install(appID: "367520", name: "Hollow Knight", in: drive)
    let games = SteamScanner.scan(steamRoot: roots.steam).games.filter { $0.steamID == "367520" }
    #expect(games.count == 1)
    #expect(games.first?.path.hasSuffix("/Steam/steamapps/common/Hollow Knight") == true)
}

/// A manifest without a name still shows the game, under its folder's name.
@Test func aSteamGameWithoutANameShowsItsFolderName() throws {
    let roots = try fixtureRoots()
    try #"""
    "AppState" { "appid" "504230" "StateFlags" "4" "installdir" "Celeste" }
    """#.write(to: roots.steam.appending(path: "steamapps/appmanifest_504230.acf"), atomically: true, encoding: .utf8)
    #expect(SteamScanner.scan(steamRoot: roots.steam).games.first { $0.steamID == "504230" }?.title == "Celeste")
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
/// A stand-in for the internet: answers by URL, counts the requests, can go offline.
actor FakeWeb {
    var requests: [URLRequest] = []
    var online = true
    let answers: [String: String]
    init(_ answers: [String: String]) { self.answers = answers }
    func goOffline() { online = false }
    func count(_ part: String) -> Int { requests.filter { $0.url!.absoluteString.contains(part) }.count }
    func answer(_ request: URLRequest) throws -> Data {
        requests.append(request)
        guard online else { throw URLError(.notConnectedToInternet) }
        let url = request.url!.absoluteString
        if let match = answers.first(where: { url.contains($0.key) }) { return Data(match.value.utf8) }
        if url.contains(".jpg") || url.contains(".png") { return Data(repeating: 7, count: 4096) }
        throw URLError(.fileDoesNotExist)
    }
}

let storeAssets = #"{"response":{"store_items":[{"assets":{"asset_url_format":"steam/apps/1546710/${FILENAME}?t=1","library_capsule_2x":"ab12/library_capsule_2x.jpg"}}]}}"#

@Test func steamArtComesFromTheStoresAssetListOnceAndIsCached() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarCovers-\(UUID().uuidString)")
    let web = FakeWeb(["IStoreBrowseService": storeAssets])
    let cache = CoverCache(folder: folder) { try await web.answer($0) }
    let first = await cache.cover(steamID: "1546710")
    #expect(first == folder.appending(path: "steam-1546710.jpg"))
    #expect(await web.count("ab12/library_capsule_2x.jpg") == 1)
    await web.goOffline()
    #expect(await cache.cover(steamID: "1546710") == first)
    #expect(await web.count("IStoreBrowseService") == 1)
}

@Test func offlineWithNothingCachedTheGeneratedCoverShowsAndIsntAskedAgain() async {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarCovers-\(UUID().uuidString)")
    let web = FakeWeb([:])
    await web.goOffline()
    let cache = CoverCache(folder: folder) { try await web.answer($0) }
    #expect(await cache.cover(steamID: "1") == nil)
    let asked = await web.requests.count
    #expect(await cache.cover(steamID: "1") == nil)
    #expect(await web.requests.count == asked)
}

@Test func steamGridDBFillsInWithAKeyAndFindsGamesByName() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarCovers-\(UUID().uuidString)")
    let web = FakeWeb([
        "IStoreBrowseService": #"{"response":{"store_items":[{}]}}"#,
        "apps/758870/library_600x900": "missing",
        "grids/steam/758870": #"{"success":true,"data":[{"url":"https://cdn2.steamgriddb.com/grid/k.png"}]}"#,
        "search/autocomplete/Moonlit%20Harbor": #"{"success":true,"data":[{"id":42,"name":"Moonlit Harbor"}]}"#,
        "grids/game/42": #"{"success":true,"data":[{"url":"https://cdn2.steamgriddb.com/grid/m.png"}]}"#,
    ])
    let cache = CoverCache(folder: folder) { try await web.answer($0) }
    // No key: nothing by name.
    #expect(await cache.cover(title: "Moonlit Harbor") == nil)
    await cache.setGridKey("  secret ")
    #expect(await cache.cover(title: "Moonlit Harbor") == folder.appending(path: "grid-moonlit-harbor.jpg"))
    let grid = await web.requests.first { $0.url!.absoluteString.contains("grids/game") }
    #expect(grid?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    #expect(SteamStore.assets(from: Data(storeAssets.utf8)).cover?.absoluteString
            == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1546710/ab12/library_capsule_2x.jpg?t=1")
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
    #expect(Steam(root: steam).isSignedIn)
    try FileManager.default.removeItem(at: steam.appending(path: "config/loginusers.vdf"))
    #expect(!Steam(root: steam).isSignedIn)
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

@Test func theLibraryFileKeepsItsFormatAndSetsADamagedFileAside() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarTests-library-\(UUID().uuidString)")
    let file = LibraryFile.file(at: folder.appending(path: "library.json"))
    var game = Game(id: "app:/x", title: "X", source: .macApp, path: "/Applications/X.app")
    game.added = Date(timeIntervalSince1970: 1_700_000_000)
    try file.save(LibraryFile(games: [game], steamFolder: "/Volumes/Games/Steam"))
    let text = try String(contentsOf: file.url, encoding: .utf8)
    #expect(text.contains("\"2023-11-14T22:13:20Z\""))
    #expect(try file.load() == LibraryFile(games: [game], steamFolder: "/Volumes/Games/Steam"))

    try Data("{ not json".utf8).write(to: file.url)
    #expect(throws: JSONFile<LibraryFile>.Damaged.self) { try file.load(setAsideDamaged: true) }
    #expect(!file.exists)
    let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(kept.contains { $0.hasPrefix("library (damaged ") })
}
