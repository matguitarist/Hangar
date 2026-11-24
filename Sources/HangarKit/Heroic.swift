import Foundation

/// Where Heroic installed a game, and how Heroic names it: its store ("legendary" for Epic,
/// "gog", "sideload") and its app name there. Heroic launches it (S-036).
public struct HeroicGame: Codable, Sendable, Hashable {
    public var runner: String
    public var appName: String
    /// The cover Heroic shows, a web URL, or nil.
    public var art: String?

    public init(runner: String, appName: String, art: String? = nil) {
        self.runner = runner
        self.appName = appName
        self.art = art
    }

    /// "Epic", "GOG", or nil for a game added to Heroic by hand.
    public var store: String? {
        switch runner {
        case "legendary": "Epic"
        case "gog": "GOG"
        default: nil
        }
    }

    /// heroic://launch?appName=…&runner=…, which Heroic opens with its own settings for the game.
    public var launchURL: URL? {
        var parts = URLComponents()
        parts.scheme = "heroic"
        parts.host = "launch"
        parts.queryItems = [URLQueryItem(name: "appName", value: appName), URLQueryItem(name: "runner", value: runner)]
        return parts.url
    }
}

/// The games Heroic installed: Epic through Legendary, GOG, and apps added to Heroic by hand.
/// Reads Heroic's own files in ~/Library/Application Support/heroic; never changes them.
public enum HeroicScanner {
    public static func scan(config: URL) -> [Game] {
        guard FileManager.default.fileExists(atPath: config.path) else { return [] }
        return epic(config) + gog(config) + sideloaded(config)
    }

    /// legendaryConfig/legendary/installed.json: { appName: { title, install_path, executable, platform, is_dlc } }.
    static func epic(_ config: URL) -> [Game] {
        guard let installed = json(config.appending(path: "legendaryConfig/legendary/installed.json")) as? [String: Any] else { return [] }
        let art = covers(config.appending(path: "store_cache/legendary_library.json"))
        return installed.keys.sorted().compactMap { key in
            guard let entry = installed[key] as? [String: Any], entry["is_dlc"] as? Bool != true,
                  let path = entry["install_path"] as? String, !path.isEmpty else { return nil }
            let title = entry["title"] as? String ?? key
            let exe = (entry["executable"] as? String).map { URL(fileURLWithPath: path).appending(path: $0).path }
            return game(runner: "legendary", appName: key, title: title, folder: path, exe: exe,
                        mac: (entry["platform"] as? String)?.lowercased() == "mac", art: art[key])
        }
    }

    /// gog_store/installed.json: { installed: [ { appName, platform, install_path, is_dlc } ] }.
    /// Titles come from Heroic's library cache, else the game's goggame-<id>.info, else its folder.
    static func gog(_ config: URL) -> [Game] {
        guard let root = json(config.appending(path: "gog_store/installed.json")) as? [String: Any],
              let installed = root["installed"] as? [[String: Any]] else { return [] }
        var titles: [String: String] = [:]
        for file in ["store_cache/gog_library.json", "gog_store/library.json"] {
            for entry in (json(config.appending(path: file)) as? [String: Any])?["games"] as? [[String: Any]] ?? [] {
                if let id = entry["app_name"] as? String, let title = entry["title"] as? String { titles[id] = titles[id] ?? title }
            }
        }
        let art = covers(config.appending(path: "store_cache/gog_library.json"))
        return installed.compactMap { entry in
            guard let id = entry["appName"] as? String, entry["is_dlc"] as? Bool != true,
                  let path = entry["install_path"] as? String, !path.isEmpty else { return nil }
            let info = gogInfo(folder: URL(fileURLWithPath: path), id: id)
            let title = titles[id] ?? info.title ?? URL(fileURLWithPath: path).lastPathComponent
            return game(runner: "gog", appName: id, title: title, folder: path, exe: info.exe,
                        mac: (entry["platform"] as? String)?.lowercased() == "osx" || (entry["platform"] as? String)?.lowercased() == "mac",
                        art: art[id])
        }
    }

    /// sideload_apps/library.json: { games: [ { app_name, title, install: { executable, platform }, folder_name, is_installed } ] }.
    static func sideloaded(_ config: URL) -> [Game] {
        let games = (json(config.appending(path: "sideload_apps/library.json")) as? [String: Any])?["games"] as? [[String: Any]] ?? []
        return games.compactMap { entry in
            guard entry["is_installed"] as? Bool != false, let id = entry["app_name"] as? String,
                  let title = entry["title"] as? String else { return nil }
            let install = entry["install"] as? [String: Any]
            let exe = install?["executable"] as? String
            let folder = entry["folder_name"] as? String ?? exe.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } ?? ""
            guard !folder.isEmpty else { return nil }
            return game(runner: "sideload", appName: id, title: title, folder: folder, exe: exe,
                        mac: (install?["platform"] as? String)?.lowercased() == "mac", art: entry["art_cover"] as? String)
        }
    }

    static func game(runner: String, appName: String, title: String, folder: String, exe: String?, mac: Bool, art: String?) -> Game {
        var hints = [folder.hasSuffix("/") ? folder : folder + "/"]
        // Wine names a Windows program by its Windows path (Z:\…\Game.exe), so the exe's name finds it too.
        if let exe, !mac {
            let name = URL(fileURLWithPath: exe).lastPathComponent
            if !name.isEmpty { hints += ["\\" + name, "/" + name] }
        }
        var game = Game(id: "heroic:\(runner):\(appName)", title: title, source: .heroic, runner: mac ? .native : .heroic,
                        path: folder, exe: exe, processHints: hints)
        game.heroic = HeroicGame(runner: runner, appName: appName, art: art?.isEmpty == false ? art : nil)
        return game
    }

    /// A GOG game's name and main program, from goggame-<id>.info in its folder.
    static func gogInfo(folder: URL, id: String) -> (title: String?, exe: String?) {
        guard let info = json(folder.appending(path: "goggame-\(id).info")) as? [String: Any] else { return (nil, nil) }
        let tasks = info["playTasks"] as? [[String: Any]] ?? []
        let main = tasks.first { $0["isPrimary"] as? Bool == true } ?? tasks.first
        let exe = (main?["path"] as? String).map { folder.appending(path: $0.replacingOccurrences(of: "\\", with: "/")).path }
        return (info["name"] as? String, exe)
    }

    /// Cover URLs by app name, from one of Heroic's library caches ({ library|games: [ { app_name, art_cover } ] }).
    static func covers(_ file: URL) -> [String: String] {
        guard let root = json(file) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for key in ["library", "games"] {
            for entry in root[key] as? [[String: Any]] ?? [] {
                if let id = entry["app_name"] as? String, let art = (entry["art_cover"] ?? entry["art_square"]) as? String, !art.isEmpty {
                    result[id] = art
                }
            }
        }
        return result
    }

    /// The Wine prefix Heroic runs a Windows game in (GamesConfig/<appName>.json, winePrefix), or nil.
    public static func prefix(config: URL, appName: String) -> URL? {
        guard let root = json(config.appending(path: "GamesConfig/\(appName).json")) as? [String: Any],
              let settings = root[appName] as? [String: Any], let path = settings["winePrefix"] as? String, !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func json(_ file: URL) -> Any? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
