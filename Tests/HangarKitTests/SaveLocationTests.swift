import Foundation
import Testing
@testable import HangarKit

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures")

private func page(_ name: String) throws -> GameData {
    GameData.parse(try String(contentsOf: fixtures.appending(path: "PCGamingWiki/\(name).txt"), encoding: .utf8), page: name)
}

// S-021
@Test func readsEverySaveAndConfigRow() throws {
    let data = try page("Hollow_Knight")
    #expect(data.entries.filter { $0.kind == .saves }.map(\.platform) == ["Windows", "Windows", "Microsoft Store", "OS X", "Linux"])
    #expect(data.entries.filter { $0.kind == .config }.count == 6)
    #expect(data.entries.first { $0.kind == .saves }?.path == #"{{p|userprofile}}\AppData\LocalLow\Team Cherry\Hollow Knight\*.dat"#)
    #expect(data.url.absoluteString == "https://www.pcgamingwiki.com/wiki/Hollow_Knight")
}

@Test func windowsPathsLandInsideTheBottle() throws {
    let bottle = URL(fileURLWithPath: "/B/Steam")
    let context = SavePathContext(userProfile: bottle.appending(path: "drive_c/users/crossover"), driveC: bottle.appending(path: "drive_c"),
                                  home: URL(fileURLWithPath: "/Users/me"), game: URL(fileURLWithPath: "/B/Steam/drive_c/Games/HK"),
                                  steam: URL(fileURLWithPath: "/B/Steam/drive_c/Program Files (x86)/Steam"))
    func resolve(_ s: String) -> String? { SavePaths.resolve(s, context: context) }
    #expect(resolve(#"{{p|userprofile}}\AppData\LocalLow\Team Cherry\Hollow Knight\*.dat"#)
            == "/B/Steam/drive_c/users/crossover/AppData/LocalLow/Team Cherry/Hollow Knight/*.dat")
    #expect(resolve(#"{{p|appdata}}\StardewValley\Saves\"#) == "/B/Steam/drive_c/users/crossover/AppData/Roaming/StardewValley/Saves")
    #expect(resolve(#"{{p|localappdata}}\X"#) == "/B/Steam/drive_c/users/crossover/AppData/Local/X")
    #expect(resolve(#"{{p|userprofile\Documents}}\My Games\X"#) == "/B/Steam/drive_c/users/crossover/Documents/My Games/X")
    #expect(resolve(#"{{P|userprofile\AppData\LocalLow}}\X"#) == "/B/Steam/drive_c/users/crossover/AppData/LocalLow/X")
    #expect(resolve(#"{{p|programdata}}\X"#) == "/B/Steam/drive_c/ProgramData/X")
    #expect(resolve(#"{{p|public}}\Documents\X"#) == "/B/Steam/drive_c/users/Public/Documents/X")
    #expect(resolve(#"{{p|game}}\hollow_knight_Data\Config.ini"#) == "/B/Steam/drive_c/Games/HK/hollow_knight_Data/Config.ini")
    #expect(resolve(#"{{p|steam}}\userdata\{{p|uid}}\367520\remote\"#) == "/B/Steam/drive_c/Program Files (x86)/Steam/userdata/*/367520/remote")
    #expect(resolve(#"{{p|hkcu}}\Software\Team Cherry\Hollow Knight\"#) == nil)
}

@Test func macPathsLandInTheHomeFolder() {
    let context = SavePathContext(home: URL(fileURLWithPath: "/Users/me"))
    #expect(SavePaths.resolve("{{p|osxhome}}/Library/Application Support/unity.Team Cherry.Hollow Knight/", context: context)
            == "/Users/me/Library/Application Support/unity.Team Cherry.Hollow Knight")
    // A Mac game has no Windows profile.
    #expect(SavePaths.resolve(#"{{p|appdata}}\X"#, context: context) == nil)
}

@Test func aMacGameGetsItsMacRowsAndFindsItsSaves() throws {
    let data = try page("Hollow_Knight")
    let locations = SavePaths.locations(data, isWindows: false, onSteam: true, context: SavePathContext(home: fixtures.appending(path: "Home")))
    #expect(locations.map(\.kind) == [.saves, .config])
    let saves = try #require(locations.first)
    #expect(saves.exists)
    #expect(saves.folder.lastPathComponent == "unity.Team Cherry.Hollow Knight")
    #expect(!locations[1].exists)
}

@Test func aWindowsGameFindsItsSavesWithWildcards() throws {
    let data = try page("Vernal_Edge")
    let bottle = fixtures.appending(path: "Bottles/Steam")
    let driveC = bottle.appending(path: "drive_c")
    let context = SavePathContext(userProfile: SavePathContext.userProfile(driveC: driveC), driveC: driveC, home: URL(fileURLWithPath: "/nowhere"),
                                  steam: driveC.appending(path: "Program Files (x86)/Steam"))
    let locations = SavePaths.locations(data, isWindows: true, onSteam: true, context: context)
    #expect(locations.map(\.kind) == [.saves, .saves, .config])
    #expect(locations.allSatisfy { $0.exists })
    #expect(locations[0].folder.lastPathComponent == "SaveGames")
    #expect(locations[1].found.first?.path.hasSuffix("userdata/40001/1546710/remote") == true)
}

@Test func wildcardFilesShowTheirFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "hangar-saves-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("a".utf8).write(to: folder.appending(path: "user1.DAT"))
    try Data("b".utf8).write(to: folder.appending(path: "notes.txt"))
    let found = SavePaths.matches(folder.path + "/*.dat")
    #expect(found.map(\.lastPathComponent) == ["user1.DAT"])
    let location = SaveLocation(kind: .saves, path: folder.path + "/*.dat", found: found)
    #expect(location.folder.standardizedFileURL == folder.standardizedFileURL)
}

@Test func theCacheKeepsPagesAMonthAndWorksOffline() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "hangar-pcgw-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calls = Counter()
    let clock = Clock()
    let online = GameDataCache(folder: folder, fetch: { page in
        calls.add()
        return ("Hollow_Knight", try String(contentsOf: fixtures.appending(path: "PCGamingWiki/Hollow_Knight.txt"), encoding: .utf8))
    }, now: { clock.now })
    #expect(await online.data(for: "Hollow Knight")?.entries.isEmpty == false)
    #expect(await online.data(for: "Hollow Knight") != nil)
    #expect(calls.value == 1)
    clock.now = clock.now.addingTimeInterval(31 * 86400)
    let offline = GameDataCache(folder: folder, fetch: { _ in throw URLError(.notConnectedToInternet) }, now: { clock.now })
    #expect(await offline.data(for: "Hollow Knight")?.page == "Hollow_Knight")
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date {
        get { lock.withLock { date } }
        set { lock.withLock { date = newValue } }
    }
}
