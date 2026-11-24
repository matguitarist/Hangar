import Foundation

/// The known-good setup for a game: runner and settings, from Hangar's recipe manifest.
public struct Recipe: Codable, Sendable, Equatable, Identifiable {
    public struct Match: Codable, Sendable, Equatable {
        public var steamID: String?
        public var title: String?
        /// The game's program file name, "MoonlitHarbor.exe".
        public var exe: String?

        public init(steamID: String? = nil, title: String? = nil, exe: String? = nil) {
            self.steamID = steamID
            self.title = title
            self.exe = exe
        }
    }

    public struct RegistryValue: Codable, Sendable, Equatable {
        /// "user" (user.reg, HKEY_CURRENT_USER) or "system" (system.reg, HKEY_LOCAL_MACHINE).
        public var hive: String
        public var key: String
        public var name: String
        public var value: String?
        public var dword: UInt32?

        public init(hive: String, key: String, name: String, value: String? = nil, dword: UInt32? = nil) {
            self.hive = hive
            self.key = key
            self.name = name
            self.value = value
            self.dword = dword
        }

        var raw: String { dword.map { String(format: "dword:%08x", $0) } ?? "\"\(value ?? "")\"" }
        var file: String { hive == "system" ? "system.reg" : "user.reg" }
    }

    public struct FileCopy: Codable, Sendable, Equatable {
        /// "@bottle/windows/system32/x.dll" or "@game/x.dll".
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public var id: String
    public var title: String
    public var match: Match
    public var graphics: GraphicsBackend?
    public var msync: Bool?
    public var highResolution: Bool?
    public var metalFX: Bool?
    public var avx: Bool?
    public var env: [String: String]?
    public var arguments: String?
    public var dllOverrides: [String: String]?
    public var registry: [RegistryValue]?
    public var copies: [FileCopy]?
    public var notes: String?
    /// The runner it was tested with, "CrossOver 26.3".
    public var tested: String?
    public var source: String?

    public init(id: String, title: String, match: Match) {
        self.id = id
        self.title = title
        self.match = match
    }

    /// True when the recipe is for this game.
    public func matches(_ game: Game) -> Bool {
        if let steamID = match.steamID { return game.steamID == steamID }
        if let exe = match.exe?.lowercased(), !exe.isEmpty {
            let names = ([game.exe, game.options.exe, game.path].compactMap { $0 } + game.processHints)
                .map { $0.replacingOccurrences(of: "\\", with: "/").lowercased() }
            if names.contains(where: { $0.hasSuffix("/" + exe) || $0 == exe }) { return true }
        }
        if let title = match.title { return title.caseInsensitiveCompare(game.title) == .orderedSame }
        return false
    }

    /// Problems that make the entry unusable, or none.
    public var problems: [String] {
        var problems: [String] = []
        if id.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("no id") }
        if match.steamID == nil && match.title == nil && match.exe == nil { problems.append("matches no game") }
        for value in registry ?? [] {
            if value.hive != "user" && value.hive != "system" { problems.append("registry hive \(value.hive)") }
            if (value.value == nil) == (value.dword == nil) { problems.append("registry \(value.name) needs a value or a dword") }
        }
        for copy in copies ?? [] {
            for path in [copy.from, copy.to] where !(path.hasPrefix("@bottle/") || path.hasPrefix("@game/")) || path.contains("..") {
                problems.append("copy path \(path)")
            }
        }
        for (name, value) in env ?? [:] where name.isEmpty || name.contains("=") || value.contains("\0") {
            problems.append("variable \(name)")
        }
        return problems
    }
}

/// One change a recipe makes, as the preview lists it.
public enum RecipeChange: Sendable, Equatable {
    case graphics(GraphicsBackend)
    case setting(String, Bool)
    case variable(String, String)
    case arguments(String)
    case dllOverride(String, String)
    case registry(Recipe.RegistryValue)
    case copy(Recipe.FileCopy)

    public var text: String {
        switch self {
        case let .graphics(b): String(localized: "Graphics: \(b.title)", bundle: .main)
        case let .setting(name, on): on ? String(localized: "Turn on \(name)", bundle: .main) : String(localized: "Turn off \(name)", bundle: .main)
        case let .variable(name, value): String(localized: "Set the variable \(name) to \(value)", bundle: .main)
        case let .arguments(args): String(localized: "Launch arguments: \(args)", bundle: .main)
        case let .dllOverride(dll, mode): String(localized: "Load \(dll).dll as \(mode)", bundle: .main)
        case let .registry(v): String(localized: "Registry: \(v.key) › \(v.name)", bundle: .main)
        case let .copy(c): String(localized: "Copy \(c.from) to \(c.to)", bundle: .main)
        }
    }
}

extension Recipe {
    /// What applying the recipe changes, in order.
    public var changes: [RecipeChange] {
        var list: [RecipeChange] = []
        if let graphics { list.append(.graphics(graphics)) }
        if let msync { list.append(.setting("MSync", msync)) }
        if let highResolution { list.append(.setting(String(localized: "High Resolution Mode", bundle: .main), highResolution)) }
        if let metalFX { list.append(.setting("MetalFX", metalFX)) }
        if let avx { list.append(.setting(String(localized: "AVX for Rosetta", bundle: .main), avx)) }
        for (name, value) in (env ?? [:]).sorted(by: { $0.key < $1.key }) { list.append(.variable(name, value)) }
        if let arguments, !arguments.isEmpty { list.append(.arguments(arguments)) }
        for (dll, mode) in (dllOverrides ?? [:]).sorted(by: { $0.key < $1.key }) { list.append(.dllOverride(dll, mode)) }
        for value in registry ?? [] { list.append(.registry(value)) }
        for copy in copies ?? [] { list.append(.copy(copy)) }
        return list
    }

    /// A "@bottle/…" or "@game/…" path as a path in the bottle, or nil when the game's folder isn't known.
    static func bottlePath(_ path: String, game: Game, bottle: URL) -> String? {
        if path.hasPrefix("@bottle/") { return String(path.dropFirst("@bottle/".count)) }
        guard path.hasPrefix("@game/"), let folder = gameFolder(game, bottle: bottle) else { return nil }
        return folder + "/" + String(path.dropFirst("@game/".count))
    }

    /// The game's folder in the bottle ("drive_c/Program Files/Moonlit Harbor"): from its program,
    /// or for a Start menu shortcut, the Program Files folder named like the game.
    static func gameFolder(_ game: Game, bottle: URL) -> String? {
        func inBottle(_ program: String) -> String? {
            let p = program.replacingOccurrences(of: "\\", with: "/")
            if p.count > 2, p.dropFirst().hasPrefix(":/") {
                let drive = "drive_\(p.prefix(1).lowercased())/"
                return (drive + p.dropFirst(3)).split(separator: "/").dropLast().joined(separator: "/")
            }
            let base = bottle.standardizedFileURL.path + "/"
            let full = URL(fileURLWithPath: p).deletingLastPathComponent().standardizedFileURL.path
            return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : nil
        }
        if let exe = game.options.exe, let folder = inBottle(exe) { return folder }
        if let exe = game.exe, !game.startsShortcut, !exe.lowercased().hasSuffix(".lnk"), let folder = inBottle(exe) { return folder }
        for programs in ["drive_c/Program Files", "drive_c/Program Files (x86)"] {
            let folder = "\(programs)/\(game.title)"
            if FileManager.default.fileExists(atPath: bottle.appending(path: folder).path) { return folder }
        }
        return nil
    }

    /// The bottle files applying the recipe writes (for the snapshot before it).
    public func touchedFiles(game: Game, bottle: URL) -> [String] {
        var files = ["cxbottle.conf", "user.reg", "system.reg"]
        for copy in copies ?? [] { if let to = Self.bottlePath(copy.to, game: game, bottle: bottle) { files.append(to) } }
        return files
    }

    /// Whether everything the recipe copies can be found, so applying won't stop halfway.
    public func check(game: Game, bottle: URL) throws(RecipeError) {
        for copy in copies ?? [] {
            guard let from = Self.bottlePath(copy.from, game: game, bottle: bottle), Self.bottlePath(copy.to, game: game, bottle: bottle) != nil else {
                throw .noGameFolder
            }
            guard FileManager.default.fileExists(atPath: bottle.appending(path: from).path) else { throw .missingFile(copy.from) }
        }
    }

    /// Writes the recipe into the bottle and returns the game's new options.
    public func apply(to game: Game, bottle: URL) throws -> GameOptions {
        try check(game: game, bottle: bottle)
        var settings = BottleSettings.read(bottle: bottle)
        if let graphics { settings.graphics = graphics }
        if let msync { settings.msync = msync }
        if let highResolution { settings.highResolution = highResolution }
        if let metalFX { settings.metalFX = metalFX }
        if let avx { settings.avx = avx }
        try settings.write(bottle: bottle)

        let regs = Dictionary(grouping: (registry ?? []), by: \.file)
        let overrides = dllOverrides ?? [:]
        for file in ["user.reg", "system.reg"] where !(regs[file] ?? []).isEmpty || (file == "user.reg" && !overrides.isEmpty) {
            let url = bottle.appending(path: file)
            var reg = (try? RegFile.read(url)) ?? RegFile(text: "WINE REGISTRY Version 2\n")
            if file == "user.reg" {
                for (dll, mode) in overrides.sorted(by: { $0.key < $1.key }) { reg.setString(dll, mode, in: "Software\\Wine\\DllOverrides") }
            }
            for value in regs[file] ?? [] { reg.set(value.name, raw: value.raw, in: value.key) }
            try reg.write(to: url)
        }

        let fm = FileManager.default
        for copy in copies ?? [] {
            guard let from = Self.bottlePath(copy.from, game: game, bottle: bottle), let to = Self.bottlePath(copy.to, game: game, bottle: bottle) else {
                throw RecipeError.noGameFolder
            }
            guard fm.fileExists(atPath: bottle.appending(path: from).path) else { throw RecipeError.missingFile(copy.from) }
            let target = bottle.appending(path: to)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: bottle.appending(path: from), to: target)
        }

        var options = game.options
        for (name, value) in (env ?? [:]).sorted(by: { $0.key < $1.key }) {
            options.variables.removeAll { $0.name == name }
            options.variables.append(EnvironmentVariable(name: name, value: value))
        }
        if let arguments, !arguments.isEmpty { options.arguments = arguments }
        return options
    }
}

public enum RecipeError: Error, Equatable {
    /// Hangar can't tell which folder of the bottle holds the game.
    case noGameFolder
    /// A file the recipe copies isn't in the bottle.
    case missingFile(String)
}

/// The recipe manifest: { "schema": 1, "recipes": [ … ] }.
public struct RecipeManifest: Sendable {
    public var recipes: [Recipe]
    /// Entries left out, with why: a bad entry is skipped, never fatal.
    public var skipped: [String]

    public static let schema = 1

    public init(recipes: [Recipe] = [], skipped: [String] = []) {
        self.recipes = recipes
        self.skipped = skipped
    }

    public static func parse(_ data: Data) -> RecipeManifest {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return RecipeManifest(skipped: ["the manifest isn't JSON"])
        }
        if let schema = root["schema"] as? Int, schema > Self.schema {
            return RecipeManifest(skipped: ["schema \(schema) is newer than this Hangar"])
        }
        var manifest = RecipeManifest()
        for (index, entry) in ((root["recipes"] as? [Any]) ?? []).enumerated() {
            guard let json = try? JSONSerialization.data(withJSONObject: entry) else { continue }
            do {
                let recipe = try JSONDecoder().decode(Recipe.self, from: json)
                let problems = recipe.problems
                if problems.isEmpty, !manifest.recipes.contains(where: { $0.id == recipe.id }) {
                    manifest.recipes.append(recipe)
                } else {
                    manifest.skipped.append("\(recipe.id.isEmpty ? "#\(index)" : recipe.id): \(problems.isEmpty ? "duplicate id" : problems.joined(separator: ", "))")
                }
            } catch {
                manifest.skipped.append("#\(index): \(Self.describe(error))")
            }
        }
        return manifest
    }

    static func describe(_ error: Error) -> String {
        switch error as? DecodingError {
        case let .keyNotFound(key, _): "missing \(key.stringValue)"
        case let .typeMismatch(_, context), let .valueNotFound(_, context): "wrong type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .dataCorrupted(context): "bad value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        default: error.localizedDescription
        }
    }

    public func recipe(for game: Game) -> Recipe? { recipes.first { $0.matches(game) } }
}
