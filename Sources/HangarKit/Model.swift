import Foundation

/// Where Hangar found a game.
public enum GameSource: String, Codable, Sendable, CaseIterable {
    case steam, crossOver, macApp, addedByHand
    /// Installed by Heroic: Epic, GOG, or added to Heroic by hand (S-036).
    case heroic
}

/// What runs a game.
public enum RunnerKind: String, Codable, Sendable {
    /// A Mac app, started with open.
    case native
    /// A Windows program in a CrossOver bottle.
    case crossOver
    /// A Windows program run by a Wine build in a prefix of its own.
    case wine
    /// A Windows program run by Apple's Game Porting Toolkit in a prefix of its own.
    case gamePortingToolkit
    /// MacRunner, found on the Runners page.
    case macRunner
    /// A Windows game Heroic installed, started through Heroic with its own Wine settings (S-036).
    case heroic
}

/// A game in the library: a Mac app, a Steam game, or a Windows program in a bottle.
/// Every field after source has a default, so older libraries still open.
public struct Game: Codable, Sendable, Identifiable, Hashable {
    /// Stable across scans: the source and the store id or path.
    public var id: String
    public var title: String
    public var source: GameSource
    public var runner: RunnerKind = .native
    /// The Steam app id, for Steam games (on the Mac or in a bottle).
    public var steamID: String?
    /// The game's folder or .app on this Mac.
    public var path: String = ""
    /// For a Windows game: what to run, as a Windows path ("C:/…/Game.exe") or a shortcut to start.
    public var exe: String?
    /// For a Windows game: start it with wine --start (a .lnk shortcut) instead of --cx-app.
    public var startsShortcut: Bool = false
    /// The CrossOver bottle a Windows game lives in.
    public var bottle: String?
    /// Words that find the game's own process in the process list (its folder, its exe name).
    public var processHints: [String] = []
    /// Seconds played from Hangar.
    public var playtime: TimeInterval = 0
    public var lastPlayed: Date?
    /// Each time it was played from Hangar, oldest first (S-044).
    public var sessions: [PlaySession] = []
    /// How the last launch went, and how many launches there were (S-045).
    public var lastLaunch: LaunchRecord?
    public var launches = 0
    /// An image the person chose, or nil for the automatic cover.
    public var customCover: String?
    public var added: Date = Date(timeIntervalSince1970: 0)
    /// What the person set on the game's Settings tab.
    public var options = GameOptions()
    /// For a game Heroic installed: how Heroic names it (S-036).
    public var heroic: HeroicGame?

    public init(id: String, title: String, source: GameSource, runner: RunnerKind = .native,
                steamID: String? = nil, path: String = "", exe: String? = nil, bottle: String? = nil,
                processHints: [String] = []) {
        self.id = id
        self.title = title
        self.source = source
        self.runner = runner
        self.steamID = steamID
        self.path = path
        self.exe = exe
        self.bottle = bottle
        self.processHints = processHints
    }

    enum CodingKeys: String, CodingKey {
        case id, title, source, runner, steamID, path, exe, startsShortcut, bottle, processHints
        case playtime, lastPlayed, customCover, added, options, heroic, sessions, lastLaunch, launches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        source = try c.decodeIfPresent(GameSource.self, forKey: .source) ?? .addedByHand
        runner = try c.decodeIfPresent(RunnerKind.self, forKey: .runner) ?? .native
        steamID = try c.decodeIfPresent(String.self, forKey: .steamID)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        exe = try c.decodeIfPresent(String.self, forKey: .exe)
        startsShortcut = try c.decodeIfPresent(Bool.self, forKey: .startsShortcut) ?? false
        bottle = try c.decodeIfPresent(String.self, forKey: .bottle)
        processHints = try c.decodeIfPresent([String].self, forKey: .processHints) ?? []
        playtime = try c.decodeIfPresent(TimeInterval.self, forKey: .playtime) ?? 0
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        customCover = try c.decodeIfPresent(String.self, forKey: .customCover)
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date(timeIntervalSince1970: 0)
        options = try c.decodeIfPresent(GameOptions.self, forKey: .options) ?? GameOptions()
        heroic = try c.decodeIfPresent(HeroicGame.self, forKey: .heroic)
        sessions = try c.decodeIfPresent([PlaySession].self, forKey: .sessions) ?? []
        lastLaunch = try c.decodeIfPresent(LaunchRecord.self, forKey: .lastLaunch)
        launches = try c.decodeIfPresent(Int.self, forKey: .launches) ?? 0
    }

    /// What the person did with the game, which a rescan or a move to its own bottle keeps.
    /// Every new field of that kind goes here, so no caller forgets one.
    public mutating func keepPersonalData(from other: Game) {
        playtime = other.playtime
        lastPlayed = other.lastPlayed
        sessions = other.sessions
        lastLaunch = other.lastLaunch
        launches = other.launches
        customCover = other.customCover
        options = other.options
        added = other.added
    }

    /// A Windows game (one that runs through a runner other than Mac).
    public var isWindows: Bool { runner != .native }

    /// A game Heroic runs: its Wine settings live in Heroic, not in a CrossOver bottle.
    public var isHeroic: Bool { heroic != nil }
}

/// A game's own settings, kept across scans. Every field has a default, so older libraries open.
public struct GameOptions: Codable, Sendable, Hashable {
    /// Metal's performance HUD over the game (MTL_HUD_ENABLED=1).
    public var metalHUD = false
    /// Launch arguments as typed, split like a shell would ("-windowed -name 'Big Map'").
    public var arguments = ""
    /// Environment variables the person added.
    public var variables: [EnvironmentVariable] = []
    /// For a Windows program: another exe to run, as a Windows path.
    public var exe: String?
    /// For a Windows program: a Wine build or Game Porting Toolkit to run it with (its path on the
    /// Runners page) instead of CrossOver. Nil runs it in its bottle.
    public var runner: String?
    /// Other settings on battery (S-025); nil uses the same settings everywhere.
    public var battery: BatteryProfile?
    /// A frame rate limit for DXVK games (S-038): nil none, 0 the display's rate.
    public var frameCap: Int?

    public init(metalHUD: Bool = false, arguments: String = "", variables: [EnvironmentVariable] = [], exe: String? = nil) {
        self.metalHUD = metalHUD
        self.arguments = arguments
        self.variables = variables
        self.exe = exe
    }

    enum CodingKeys: String, CodingKey { case metalHUD, arguments, variables, exe, runner, battery, frameCap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        variables = try c.decodeIfPresent([EnvironmentVariable].self, forKey: .variables) ?? []
        exe = try c.decodeIfPresent(String.self, forKey: .exe)
        runner = try c.decodeIfPresent(String.self, forKey: .runner)
        battery = try c.decodeIfPresent(BatteryProfile.self, forKey: .battery)
        frameCap = try c.decodeIfPresent(Int.self, forKey: .frameCap)
    }

    /// The environment variables a launch adds.
    public var environment: [String: String] {
        var env: [String: String] = [:]
        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        for variable in variables {
            let name = variable.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { env[name] = variable.value }
        }
        return env
    }

    /// The launch arguments, one per word.
    public var argumentList: [String] { ShellWords.split(arguments) }
}

/// NAME=value for a launch.
public struct EnvironmentVariable: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Splits typed launch arguments the way a shell does: spaces separate words,
/// quotes keep spaces, a backslash keeps the next character.
public enum ShellWords {
    public static func split(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for c in text {
            if escaped { word.append(c); escaped = false; inWord = true; continue }
            if c == "\\", quote != "'" { escaped = true; inWord = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { word.append(c) }
                continue
            }
            if c == "\"" || c == "'" { quote = c; inWord = true; continue }
            if c.isWhitespace {
                if inWord { words.append(word); word = ""; inWord = false }
                continue
            }
            word.append(c)
            inWord = true
        }
        if inWord { words.append(word) }
        return words
    }
}

/// A list of games the person makes.
public struct GameCollection: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var gameIDs: [String]

    public init(id: UUID = UUID(), name: String, gameIDs: [String] = []) {
        self.id = id
        self.name = name
        self.gameIDs = gameIDs
    }
}

/// Everything Hangar saves: library.json.
public struct LibraryFile: Codable, Sendable, Equatable {
    public var games: [Game] = []
    public var collections: [GameCollection] = []
    /// Games the person removed; a scan doesn't bring them back.
    public var removed: [Game] = []
    /// A Steam folder the person chose, when Steam isn't in its usual place.
    public var steamFolder: String?

    public init(games: [Game] = [], collections: [GameCollection] = [], removed: [Game] = [], steamFolder: String? = nil) {
        self.games = games
        self.collections = collections
        self.removed = removed
        self.steamFolder = steamFolder
    }

    enum CodingKeys: String, CodingKey { case games, collections, removed, steamFolder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        games = try c.decodeIfPresent([Game].self, forKey: .games) ?? []
        collections = try c.decodeIfPresent([GameCollection].self, forKey: .collections) ?? []
        removed = try c.decodeIfPresent([Game].self, forKey: .removed) ?? []
        steamFolder = try c.decodeIfPresent(String.self, forKey: .steamFolder)
    }

    public static func load(from url: URL) -> LibraryFile {
        guard let data = try? Data(contentsOf: url) else { return LibraryFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LibraryFile.self, from: data)) ?? LibraryFile()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Folds a scan into the library: new games join, found games get fresh paths but keep
    /// what the person did (playtime, cover), games added by hand stay, removed games stay out.
    /// Games a scan no longer finds leave the library (an app moved to the Trash).
    /// Games under an unreachable folder (an unplugged drive) stay, so they come back with the drive.
    public mutating func merge(scanned: [Game], unreachable: [String] = [], now: Date = Date()) {
        let removedIDs = Set(removed.map(\.id))
        let old = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var result: [Game] = []
        for var game in scanned where !removedIDs.contains(game.id) && seen.insert(game.id).inserted {
            if let previous = old[game.id] {
                game.keepPersonalData(from: previous)
            } else {
                game.added = now
            }
            result.append(game)
        }
        result += games.filter { game in
            !seen.contains(game.id) && (game.source == .addedByHand
                || unreachable.contains { !$0.isEmpty && game.path.hasPrefix($0) })
        }
        games = result
    }

    /// Adds a game by hand. Returns the game already in the library when the path is known.
    @discardableResult
    public mutating func add(_ game: Game, now: Date = Date()) -> Game {
        if let existing = games.first(where: { $0.path == game.path && $0.exe == game.exe }) { return existing }
        var game = game
        game.added = now
        removed.removeAll { $0.id == game.id }
        games.append(game)
        return game
    }

    /// Takes a game out of the library; its files stay on disk.
    public mutating func remove(id: String) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        removed.removeAll { $0.id == id }
        removed.append(games.remove(at: index))
    }

    /// After a game's bottle was copied for it (S-011): the copy's entry takes over what the person
    /// did with the game (playtime, cover, options, collections); the old entry and the other games
    /// found in the copy leave the library (Settings › Removed Games).
    public mutating func moveGame(from oldID: String, to newID: String) {
        guard let old = games.first(where: { $0.id == oldID }), let index = games.firstIndex(where: { $0.id == newID }) else { return }
        games[index].keepPersonalData(from: old)
        for c in collections.indices {
            collections[c].gameIDs = collections[c].gameIDs.map { $0 == oldID ? newID : $0 }
        }
        let bottle = games[index].bottle
        for other in games where other.bottle == bottle && other.id != newID { remove(id: other.id) }
        remove(id: oldID)
    }

    /// Brings a removed game back.
    public mutating func restore(id: String) {
        guard let index = removed.firstIndex(where: { $0.id == id }) else { return }
        games.append(removed.remove(at: index))
    }
}
