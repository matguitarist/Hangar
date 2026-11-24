import Foundation

/// Where a scan looks. The app uses live(); tests and the self-test use fixture folders.
public struct LibraryRoots: Sendable {
    /// The Mac's Steam folder (~/Library/Application Support/Steam).
    public var steam: URL
    /// CrossOver's bottle folder.
    public var bottles: URL
    /// CrossOver.app, or nil when it isn't installed.
    public var crossOverApp: URL?
    /// Folders holding Mac apps.
    public var appFolders: [URL]
    /// This app's bundle id, never listed as a game.
    public var ownBundleID: String?
    /// Homebrew's opt folders, where Apple's Game Porting Toolkit installs.
    public var toolFolders: [URL]
    /// Where Hangar keeps the Wine prefixes of games run by a Wine build or Game Porting Toolkit.
    public var prefixes: URL
    /// The Mac user's home, where Mac games keep their saves (~/Library/Application Support/…).
    public var home: URL
    /// Heroic's settings folder (~/Library/Application Support/heroic), read for the games it installed (S-036).
    public var heroic: URL
    /// Heroic.app, or nil when it isn't installed.
    public var heroicApp: URL?

    public init(steam: URL, bottles: URL, crossOverApp: URL?, appFolders: [URL], ownBundleID: String? = nil, toolFolders: [URL] = [],
                prefixes: URL? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, heroic: URL? = nil, heroicApp: URL? = nil) {
        self.heroic = heroic ?? home.appending(path: "Library/Application Support/heroic")
        self.heroicApp = heroicApp
        self.prefixes = prefixes ?? bottles.deletingLastPathComponent().appending(path: "Prefixes")
        self.home = home
        self.steam = steam
        self.bottles = bottles
        self.crossOverApp = crossOverApp
        self.appFolders = appFolders
        self.ownBundleID = ownBundleID
        self.toolFolders = toolFolders
    }

    /// This Mac's real folders.
    public static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser, steamFolder: String? = nil,
                            ownBundleID: String? = Bundle.main.bundleIdentifier) -> LibraryRoots {
        let support = home.appending(path: "Library/Application Support")
        let crossOverPrefs = UserDefaults(suiteName: "com.codeweavers.CrossOver")?.dictionaryRepresentation()
        let app = ["/Applications/CrossOver.app", home.appending(path: "Applications/CrossOver.app").path]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let heroicApp = ["/Applications/Heroic.app", home.appending(path: "Applications/Heroic.app").path]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        return LibraryRoots(
            steam: steamFolder.map { URL(fileURLWithPath: $0) } ?? support.appending(path: "Steam"),
            bottles: CrossOverScanner.bottleFolder(preferences: crossOverPrefs, home: home),
            crossOverApp: app,
            appFolders: [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")],
            ownBundleID: ownBundleID,
            toolFolders: [URL(fileURLWithPath: "/usr/local/opt"), URL(fileURLWithPath: "/opt/homebrew/opt")],
            prefixes: support.appending(path: "Hangar/Prefixes"),
            home: home,
            heroic: support.appending(path: "heroic"),
            heroicApp: heroicApp)
    }

    /// CrossOver's wine command, which runs a program in a bottle.
    public var wine: URL? {
        crossOverApp?.appending(path: "Contents/SharedSupport/CrossOver/bin/wine")
    }
}

/// Something a scan wants the person to know, shown on the source's sidebar row.
public enum ScanNote: Sendable, Hashable {
    /// A Steam library folder that isn't there (an unplugged drive).
    case libraryMissing(path: String)
    /// A bottle Hangar couldn't read.
    case bottleUnreadable(name: String)
}

public struct ScanResult: Sendable {
    public var games: [Game] = []
    public var notes: [ScanNote] = []
    /// Every bottle found, for the bottle picker and the sidebar.
    public var bottles: [String] = []
    /// Folders a scan couldn't reach; games under them stay in the library.
    public var unreachable: [String] {
        notes.compactMap { if case let .libraryMissing(path) = $0 { path } else { nil } }
    }

    public init() {}
}

public enum LibraryScanner {
    /// The games of a scan, on the caller's thread (tests).
    public static func scanNow(_ roots: LibraryRoots) -> [Game] {
        SteamScanner.scan(steamRoot: roots.steam).games + CrossOverScanner.scan(bottles: roots.bottles).games
            + MacAppScanner.scan(folders: roots.appFolders, excluding: roots.ownBundleID) + HeroicScanner.scan(config: roots.heroic)
    }

    /// Scans every source. Runs off the main actor: it reads many small files.
    @concurrent
    public static func scan(_ roots: LibraryRoots) async -> ScanResult {
        var result = ScanResult()
        let steam = SteamScanner.scan(steamRoot: roots.steam)
        result.games += steam.games
        result.notes += steam.notes
        let crossOver = CrossOverScanner.scan(bottles: roots.bottles)
        result.games += crossOver.games
        result.notes += crossOver.notes
        result.bottles = crossOver.bottles
        result.games += MacAppScanner.scan(folders: roots.appFolders, excluding: roots.ownBundleID)
        result.games += HeroicScanner.scan(config: roots.heroic)
        return result
    }
}

// MARK: - Steam

public enum SteamScanner {
    /// Steam's own tools that sit in steamapps like games.
    static let tools: Set<String> = ["228980", "1070560", "1391110", "1628350", "1493710", "961940", "1826330", "2180100"]

    /// Mac Steam: every library folder in libraryfolders.vdf, then each appmanifest_<id>.acf.
    public static func scan(steamRoot: URL) -> ScanResult {
        var result = ScanResult()
        for folder in libraryFolders(steamRoot: steamRoot, mapPath: { URL(fileURLWithPath: $0) }) {
            let steamapps = folder.appending(path: "steamapps")
            guard FileManager.default.fileExists(atPath: steamapps.path) else {
                result.notes.append(.libraryMissing(path: folder.path))
                continue
            }
            for app in manifests(in: steamapps) {
                let dir = steamapps.appending(path: "common").appending(path: app.installDir)
                result.games.append(Game(id: "steam:\(app.id)", title: app.name, source: .steam, runner: .native,
                                         steamID: app.id, path: dir.path, processHints: [dir.path + "/"]))
            }
        }
        return result
    }

    /// The library folders listed by libraryfolders.vdf, or Steam's own folder when the file is missing.
    static func libraryFolders(steamRoot: URL, mapPath: (String) -> URL?) -> [URL] {
        let file = steamRoot.appending(path: "steamapps/libraryfolders.vdf")
        guard let vdf = KeyValues.read(file) else {
            return FileManager.default.fileExists(atPath: steamRoot.appending(path: "steamapps").path) ? [steamRoot] : []
        }
        var folders: [URL] = []
        for (_, entry) in (vdf["libraryfolders"] ?? vdf).pairs {
            guard let path = entry["path"]?.string, let url = mapPath(path) else { continue }
            if !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { folders.append(url) }
        }
        return folders.isEmpty ? [steamRoot] : folders
    }

    public struct Manifest: Sendable, Equatable {
        public var id: String
        public var name: String
        public var installDir: String
    }

    /// Installed games in one steamapps folder, Steam's own tools left out.
    public static func manifests(in steamapps: URL) -> [Manifest] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: steamapps.path)) ?? []
        return files.filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }.sorted().compactMap { name in
            guard let state = KeyValues.read(steamapps.appending(path: name))?["AppState"],
                  let id = state["appid"]?.string, let title = state["name"]?.string,
                  let dir = state["installdir"]?.string, !tools.contains(id),
                  !title.hasPrefix("Steamworks"), !title.hasPrefix("Proton"), !title.hasPrefix("Steam Linux Runtime")
            else { return nil }
            // StateFlags 4 is "fully installed"; a game still downloading for the first time isn't playable.
            if let flags = state["StateFlags"]?.string.flatMap(Int.init), flags & 4 == 0 { return nil }
            return Manifest(id: id, name: title, installDir: dir)
        }
    }

    /// True when a Steam folder remembers a signed-in account (config/loginusers.vdf).
    public static func isSignedIn(steamRoot: URL) -> Bool {
        guard let users = KeyValues.read(steamRoot.appending(path: "config/loginusers.vdf"))?["users"] else { return false }
        return users.pairs.contains { $0.1["RememberPassword"]?.string == "1" }
    }
}

// MARK: - CrossOver

public enum CrossOverScanner {
    /// Where Steam lives inside a bottle.
    public static let steamWindowsFolder = "C:/Program Files (x86)/Steam"

    /// BottleDir from CrossOver's preferences, or the default folder.
    public static func bottleFolder(preferences: [String: Any]?, home: URL) -> URL {
        if let dir = preferences?["BottleDir"] as? String, !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }
        return home.appending(path: "Library/Application Support/CrossOver/Bottles")
    }

    public static func scan(bottles: URL) -> ScanResult {
        var result = ScanResult()
        // CrossOver keeps a "default" symlink to the default bottle: list each real bottle once.
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: bottles.path)) ?? [])
            .filter { !$0.hasPrefix(".") && !isSymlink(bottles.appending(path: $0)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in names {
            let bottle = bottles.appending(path: name)
            guard FileManager.default.fileExists(atPath: bottle.appending(path: "cxbottle.conf").path) else { continue }
            result.bottles.append(name)
            guard FileManager.default.fileExists(atPath: bottle.appending(path: "drive_c").path) else {
                result.notes.append(.bottleUnreadable(name: name))
                continue
            }
            result.games += steamGames(bottle: bottle, name: name)
            result.games += programs(bottle: bottle, name: name)
        }
        return result
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// A Windows path in a bottle ("C:\\Program Files (x86)\\Steam") as a Mac path.
    public static func macPath(_ windowsPath: String, bottle: URL) -> URL? {
        let path = windowsPath.replacingOccurrences(of: "\\", with: "/")
        guard path.count >= 2, path.dropFirst().first == ":", let letter = path.first?.lowercased() else { return nil }
        let rest = path.dropFirst(2).drop { $0 == "/" }
        let drive = letter == "c" ? bottle.appending(path: "drive_c") : bottle.appending(path: "dosdevices/\(letter):").resolvingSymlinksInPath()
        return rest.isEmpty ? drive : drive.appending(path: String(rest))
    }

    /// The bottle's Steam folder on the Mac.
    public static func steamFolder(bottle: URL) -> URL {
        bottle.appending(path: "drive_c/Program Files (x86)/Steam")
    }

    /// Steam games installed in a bottle; they launch through the bottle's Steam.
    static func steamGames(bottle: URL, name: String) -> [Game] {
        let root = steamFolder(bottle: bottle)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var games: [Game] = []
        for folder in SteamScanner.libraryFolders(steamRoot: root, mapPath: { macPath($0, bottle: bottle) }) {
            let steamapps = folder.appending(path: "steamapps")
            for app in SteamScanner.manifests(in: steamapps) {
                let dir = steamapps.appending(path: "common").appending(path: app.installDir)
                games.append(Game(id: "bottle:\(name):steam:\(app.id)", title: app.name, source: .crossOver, runner: .crossOver,
                                  steamID: app.id, path: dir.path, exe: steamWindowsFolder + "/steam.exe", bottle: name,
                                  processHints: ["steamapps\\common\\\(app.installDir)\\", "steamapps/common/\(app.installDir)/"]))
            }
        }
        return games
    }

    /// Words in a shortcut's name that mean it isn't a game.
    static let notGames = ["uninstall", "support", "help", "readme", "read me", "manual", "website", "setup", "settings", "steam"]

    /// The programs CrossOver lists for a bottle (cxmenu.conf): its Start menu and desktop shortcuts.
    /// Shortcuts to Steam games (.url) are left out: the Steam scan has them.
    static func programs(bottle: URL, name: String) -> [Game] {
        guard let text = try? String(contentsOf: bottle.appending(path: "cxmenu.conf"), encoding: .utf8) else { return [] }
        var games: [Game] = []
        var seen = Set<String>()
        for entry in MenuEntry.parse(text) {
            guard entry.path.lowercased().hasSuffix(".lnk"), let windows = entry.windowsPath else { continue }
            let title = String(entry.path.split(separator: "/").last ?? "").replacingOccurrences(of: ".lnk", with: "", options: [.caseInsensitive])
            let lower = title.lowercased()
            guard !title.isEmpty, lower != "steam", !lower.hasPrefix("steam "),
                  !notGames.contains(where: { $0 != "steam" && lower.contains($0) }) else { continue }
            let key = entry.values["Shortcut"] ?? lower
            guard seen.insert(key).inserted else { continue }
            let exe = entry.values["StartupWMClass"]
            games.append(Game(id: "bottle:\(name):program:\(key)", title: title, source: .crossOver, runner: .crossOver,
                              path: macPath(windows, bottle: bottle)?.path ?? bottle.path, exe: windows, bottle: name,
                              processHints: exe.map { ["\\" + $0, "/" + $0] } ?? []))
            games[games.count - 1].startsShortcut = true
        }
        return games
    }

    /// One [section] of cxmenu.conf.
    struct MenuEntry {
        var path: String
        var values: [String: String] = [:]

        /// "StartMenu.C^3A_ProgramData_Microsoft_Windows_Start+Menu/Programs/X/X.lnk" → "C:/ProgramData/Microsoft/Windows/Start Menu/Programs/X/X.lnk"
        var windowsPath: String? {
            guard let dot = path.firstIndex(of: ".") else { return nil }
            let parts = path[path.index(after: dot)...].split(separator: "/", maxSplits: 1)
            guard let folder = parts.first else { return nil }
            var decoded = String(folder).replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "+", with: " ")
            decoded = decoded.replacingOccurrences(of: "^3A", with: ":").replacingOccurrences(of: "^5E", with: "^")
            let rest = parts.count > 1 ? "/" + parts[1].replacingOccurrences(of: "+", with: " ") : ""
            return decoded + rest
        }

        static func parse(_ text: String) -> [MenuEntry] {
            var entries: [MenuEntry] = []
            for line in text.split(whereSeparator: \.isNewline) {
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("["), line.hasSuffix("]") {
                    entries.append(MenuEntry(path: String(line.dropFirst().dropLast())))
                } else if let eq = line.range(of: "="), !entries.isEmpty {
                    let key = line[..<eq.lowerBound].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    let value = line[eq.upperBound...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    entries[entries.count - 1].values[key] = value
                }
            }
            return entries
        }
    }
}

// MARK: - Mac apps

public enum MacAppScanner {
    /// Apps in the folders (and one folder deep, like /Applications/Games) whose category is a games category.
    public static func scan(folders: [URL], excluding ownBundleID: String?) -> [Game] {
        var games: [Game] = []
        var seen = Set<String>()
        for folder in folders {
            for app in apps(in: folder, depth: 1) where seen.insert(app.path).inserted {
                guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any],
                      isGame(category: info["LSApplicationCategoryType"] as? String) else { continue }
                if let own = ownBundleID, (info["CFBundleIdentifier"] as? String) == own { continue }
                let title = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                    ?? app.deletingPathExtension().lastPathComponent
                games.append(Game(id: "app:\(app.path)", title: title.isEmpty ? app.deletingPathExtension().lastPathComponent : title,
                                  source: .macApp, runner: .native, path: app.path, processHints: [app.path + "/"]))
            }
        }
        return games
    }

    /// public.app-category.games and its kinds (public.app-category.role-playing-games…).
    public static func isGame(category: String?) -> Bool {
        guard let category = category?.lowercased() else { return false }
        return category.hasPrefix("public.app-category.") && category.hasSuffix("games")
    }

    static func apps(in folder: URL, depth: Int) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var result: [URL] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let url = folder.appending(path: name)
            if name.hasSuffix(".app") {
                result.append(url)
            } else if depth > 0 {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    result += apps(in: url, depth: depth - 1)
                }
            }
        }
        return result
    }
}
