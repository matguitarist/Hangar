import Foundation

/// Where a game keeps its saves and settings, from PCGamingWiki's {{Game data/saves}} and
/// {{Game data/config}} templates. Each template names a platform ("Windows", "OS X", "Steam")
/// and one or more paths written with placeholders ({{p|appdata}}, {{p|osxhome}}).
public struct GameData: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case saves, config }
        public var kind: Kind
        /// The wiki's platform name, as written: "Windows", "OS X", "Steam".
        public var platform: String
        /// The path as the wiki writes it, placeholders and all.
        public var path: String
    }

    /// The wiki page the data came from ("Hollow_Knight").
    public var page: String
    public var entries: [Entry]

    public var url: URL { PCGamingWiki.pageURL(page) }

    /// Reads every {{Game data/saves|…}} and {{Game data/config|…}} on a page's source.
    public static func parse(_ source: String, page: String) -> GameData {
        var entries: [Entry] = []
        for (kind, name) in [(Entry.Kind.saves, "{{Game data/saves|"), (.config, "{{Game data/config|")] {
            var rest = source[...]
            while let start = rest.range(of: name, options: .caseInsensitive) {
                guard let end = closingBraces(in: rest, from: start.upperBound) else { break }
                let parts = Compatibility.splitTopLevel(String(rest[start.upperBound..<end]))
                rest = rest[end...]
                guard let platform = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), parts.count > 1 else { continue }
                for path in parts.dropFirst() {
                    let path = cleaned(path)
                    if !path.isEmpty { entries.append(Entry(kind: kind, platform: platform, path: path)) }
                }
            }
        }
        return GameData(page: page, entries: entries)
    }

    /// Where the template that starts before `from` closes: the index of its "}}".
    static func closingBraces(in text: Substring, from: Substring.Index) -> Substring.Index? {
        var depth = 1
        var i = from
        while i < text.endIndex {
            if text[i...].hasPrefix("{{") { depth += 1; i = text.index(i, offsetBy: 2); continue }
            if text[i...].hasPrefix("}}") {
                depth -= 1
                if depth == 0 { return i }
                i = text.index(i, offsetBy: 2)
                continue
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// A path without references and notes.
    static func cleaned(_ path: String) -> String {
        var s = path
        s = s.replacingOccurrences(of: #"<ref[^>]*/>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<ref[^>]*>[\s\S]*?</ref>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\{\{(?:note|cn|citation needed)[^{}]*\}\}"#, with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The platform rows that apply to a game: Windows (and Steam Cloud) for a Windows game,
    /// the Mac's for a Mac game.
    public static func platforms(isWindows: Bool, onSteam: Bool) -> Set<String> {
        var names: Set<String> = isWindows ? ["windows"] : ["os x", "macos", "mac os", "mac", "mac os x"]
        if onSteam { names.insert("steam") }
        return names
    }

    public func entries(isWindows: Bool, onSteam: Bool) -> [Entry] {
        let platforms = Self.platforms(isWindows: isWindows, onSteam: onSteam)
        return entries.filter { platforms.contains($0.platform.lowercased()) }
    }
}

/// The folders a game's placeholders stand for on this Mac.
public struct SavePathContext: Sendable, Equatable {
    /// The Windows user folder (drive_c/users/crossover), for a Windows game.
    public var userProfile: URL?
    /// drive_c, for a Windows game.
    public var driveC: URL?
    /// The Mac's home folder, for a Mac game.
    public var home: URL
    /// The game's own folder.
    public var game: URL?
    /// The Steam folder the game was installed by.
    public var steam: URL?

    public init(userProfile: URL? = nil, driveC: URL? = nil, home: URL, game: URL? = nil, steam: URL? = nil) {
        self.userProfile = userProfile
        self.driveC = driveC
        self.home = home
        self.game = game
        self.steam = steam
    }

    /// A bottle's or prefix's Windows user folder: drive_c/users/crossover in CrossOver,
    /// the Mac user's name in a Wine prefix, else the first user that isn't Public.
    public static func userProfile(driveC: URL, fallback: String = "crossover") -> URL {
        let users = driveC.appending(path: "users")
        for name in ["crossover", NSUserName()] where FileManager.default.fileExists(atPath: users.appending(path: name).path) {
            return users.appending(path: name)
        }
        let others = ((try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? [])
            .filter { $0 != "Public" && !$0.hasPrefix(".") }.sorted()
        return users.appending(path: others.first ?? fallback)
    }
}

/// A save or settings location on this Mac.
public struct SaveLocation: Sendable, Equatable, Identifiable {
    public var kind: GameData.Entry.Kind
    /// The path with its placeholders filled in, wildcards kept ("…/Hollow Knight/*.dat").
    public var path: String
    /// The files and folders it names that exist now. Empty when the game hasn't saved yet.
    public var found: [URL]

    public var id: String { "\(kind.rawValue):\(path)" }

    /// The folder to open in Finder: the location itself, or the folder its files are in.
    public var folder: URL {
        if let first = found.first {
            if path.contains("*") || !Self.isDirectory(first) { return first.deletingLastPathComponent() }
            return first
        }
        let url = URL(fileURLWithPath: path)
        return path.contains("*") ? url.deletingLastPathComponent() : url
    }

    public var exists: Bool { !found.isEmpty }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }
}

public enum SavePaths {
    /// Every location for a game, saves first, each found on disk or not. Registry keys are left out.
    public static func locations(_ data: GameData, isWindows: Bool, onSteam: Bool, context: SavePathContext) -> [SaveLocation] {
        var seen = Set<String>()
        var result: [SaveLocation] = []
        for kind in [GameData.Entry.Kind.saves, .config] {
            for entry in data.entries(isWindows: isWindows, onSteam: onSteam) where entry.kind == kind {
                guard let path = resolve(entry.path, context: context), seen.insert("\(kind):\(path)").inserted else { continue }
                result.append(SaveLocation(kind: kind, path: path, found: matches(path)))
            }
        }
        return result
    }

    /// A wiki path as a Mac path, or nil when it names the registry or a folder this game doesn't have.
    public static func resolve(_ template: String, context: SavePathContext) -> String? {
        var path = ""
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            path += rest[..<open.lowerBound]
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else { return nil }
            let inside = rest[open.upperBound..<close.lowerBound]
            rest = rest[close.upperBound...]
            let parts = inside.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased() == "p" else { return nil }
            guard let value = placeholder(parts[1], context: context) else { return nil }
            path += value
        }
        path += rest
        path = path.replacingOccurrences(of: "\\", with: "/")
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard path.hasPrefix("/") else { return nil }
        return path
    }

    static func placeholder(_ name: String, context: SavePathContext) -> String? {
        let key = name.lowercased().replacingOccurrences(of: "/", with: "\\")
        let profile = context.userProfile?.path
        switch key {
        case "osxhome": return context.home.path
        case "userprofile": return profile
        case "userprofile\\documents": return profile.map { $0 + "/Documents" }
        case "userprofile\\appdata\\locallow": return profile.map { $0 + "/AppData/LocalLow" }
        case "appdata": return profile.map { $0 + "/AppData/Roaming" }
        case "localappdata": return profile.map { $0 + "/AppData/Local" }
        case "public": return context.driveC.map { $0.path + "/users/Public" }
        case "programdata": return context.driveC.map { $0.path + "/ProgramData" }
        case "game": return context.game?.path
        case "steam": return context.steam?.path
        case "uid": return "*"
        default: return nil
        }
    }

    /// The files and folders a path names, following * in any part. Case is ignored, as on Windows.
    public static func matches(_ path: String) -> [URL] {
        var current = [URL(fileURLWithPath: "/")]
        for part in path.split(separator: "/").map(String.init) {
            var next: [URL] = []
            for folder in current {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                if part.contains("*") || part.contains("?") {
                    next += names.filter { fnmatch(part.lowercased(), $0.lowercased(), 0) == 0 }.sorted().map { folder.appending(path: $0) }
                } else if let name = names.first(where: { $0 == part }) ?? names.first(where: { $0.lowercased() == part.lowercased() }) {
                    next.append(folder.appending(path: name))
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }
}

public enum PCGamingWiki {
    public static func pageURL(_ page: String) -> URL {
        let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) ?? page
        return URL(string: "https://www.pcgamingwiki.com/wiki/\(encoded)")!
    }

    /// The page's wikitext through the API, which follows redirects.
    static func sourceURL(_ page: String) -> URL {
        var c = URLComponents(string: "https://www.pcgamingwiki.com/w/api.php")!
        c.queryItems = [URLQueryItem(name: "action", value: "parse"), URLQueryItem(name: "page", value: page),
                        URLQueryItem(name: "prop", value: "wikitext"), URLQueryItem(name: "redirects", value: "1"),
                        URLQueryItem(name: "format", value: "json")]
        return c.url!
    }

    /// The wikitext and the page's real title from an action=parse answer; nil for "missingtitle".
    static func source(from data: Data) -> (title: String, text: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parse = root["parse"] as? [String: Any],
              let text = (parse["wikitext"] as? [String: Any])?["*"] as? String else { return nil }
        let title = (parse["title"] as? String).map(AppleGamingWiki.pageName) ?? ""
        return (title, text)
    }
}

/// PCGamingWiki's save paths, cached in a folder: used offline, asked again at most once a month.
public actor GameDataCache {
    /// A page's source and its real title, or nil when the wiki has no such page. Throws when offline.
    public typealias Fetch = @Sendable (String) async throws -> (title: String, text: String)?

    let folder: URL
    let fetch: Fetch
    let now: @Sendable () -> Date
    public static let maxAge: TimeInterval = 30 * 86400

    public init(folder: URL, fetch: @escaping Fetch = GameDataCache.network, now: @escaping @Sendable () -> Date = { Date() }) {
        self.folder = folder
        self.fetch = fetch
        self.now = now
    }

    public static let network: Fetch = { page in
        var request = URLRequest(url: PCGamingWiki.sourceURL(page), timeoutInterval: 15)
        request.setValue("Hangar (macOS game library)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return PCGamingWiki.source(from: data)
    }

    /// Page sources in a folder (Tests/Fixtures/PCGamingWiki), for tests and snapshots.
    public static func folder(_ folder: URL) -> Fetch {
        { page in (try? String(contentsOf: folder.appending(path: "\(page).txt"), encoding: .utf8)).map { (page, $0) } }
    }

    func file(_ title: String) -> URL {
        folder.appending(path: AppleGamingWiki.pageName(title).replacingOccurrences(of: "/", with: "_") + ".json")
    }

    /// The save paths for a game, by its title. Nil when the wiki has no page, or offline with nothing cached.
    public func data(for title: String) async -> GameData? {
        await WebCacheFile<GameData>(url: file(title), maxAge: Self.maxAge).value(now: now()) {
            let page = AppleGamingWiki.pageName(title)
            return try await fetch(page).map { GameData.parse($0.text, page: $0.title.isEmpty ? page : $0.title) }
        }
    }
}
