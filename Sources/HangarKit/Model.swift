import Foundation

/// Where Hangar found a game.
public enum GameSource: String, Codable, Sendable, CaseIterable {
    case steam, crossOver, macApp, addedByHand
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
    /// An image the person chose, or nil for the automatic cover.
    public var customCover: String?
    public var added: Date = Date(timeIntervalSince1970: 0)
    /// What the person set on the game's Settings tab.
    public var options = GameOptions()

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
        case playtime, lastPlayed, customCover, added, options
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
    }

    /// A Windows game (one that runs through a runner other than Mac).
    public var isWindows: Bool { runner != .native }
}

/// A game's own settings, kept across scans. Every field has a default, so older libraries open.
public struct GameOptions: Codable, Sendable, Hashable {
    /// Metal's performance HUD over the game (MTL_HUD_ENABLED=1).
    public var metalHUD = false

    public init(metalHUD: Bool = false) {
        self.metalHUD = metalHUD
    }

    enum CodingKeys: String, CodingKey { case metalHUD }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
    }

    /// The environment variables a launch adds.
    public var environment: [String: String] {
        var env: [String: String] = [:]
        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
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
                game.playtime = previous.playtime
                game.lastPlayed = previous.lastPlayed
                game.customCover = previous.customCover
                game.added = previous.added
                game.options = previous.options
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

    /// Brings a removed game back.
    public mutating func restore(id: String) {
        guard let index = removed.firstIndex(where: { $0.id == id }) else { return }
        games.append(removed.remove(at: index))
    }
}
