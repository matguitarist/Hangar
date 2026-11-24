import Foundation

/// What a game is about (S-031): a description, who made it, when, and its genres,
/// from the Steam store for a Steam game and from TheGamesDB for the others.
public struct GameDetails: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case steam, theGamesDB }

    public var source: Source
    public var summary: String
    public var developers: [String]
    public var publishers: [String]
    /// The day it came out, when the source gives one as a date (TheGamesDB).
    public var releaseDate: Date?
    /// The day as the source writes it, when it isn't a date ("24 Feb, 2017", "Coming soon").
    public var releaseText: String?
    public var genres: [String]
    /// The game's page at the source.
    public var url: URL?
    /// Whether the store sells a macOS version (Steam's platforms); nil when the source doesn't say.
    public var hasMacVersion: Bool?

    public init(source: Source, summary: String, developers: [String] = [], publishers: [String] = [], releaseDate: Date? = nil,
                releaseText: String? = nil, genres: [String] = [], url: URL? = nil, hasMacVersion: Bool? = nil) {
        self.source = source
        self.summary = summary
        self.developers = developers
        self.publishers = publishers
        self.releaseDate = releaseDate
        self.releaseText = releaseText
        self.genres = genres
        self.url = url
        self.hasMacVersion = hasMacVersion
    }

    /// Nothing worth a section.
    public var isEmpty: Bool { summary.isEmpty && developers.isEmpty && publishers.isEmpty && genres.isEmpty }
}

/// The Steam store's appdetails: no key, in the app's language.
public enum SteamDetails {
    public static func url(appID: String, language: String) -> URL {
        var c = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        c.queryItems = [URLQueryItem(name: "appids", value: appID), URLQueryItem(name: "l", value: language)]
        return c.url!
    }

    /// Steam's name for a language ("french"), from a language code ("fr").
    public static func language(for code: String) -> String {
        ["fr": "french", "de": "german", "es": "spanish", "it": "italian", "ja": "japanese", "pt": "portuguese",
         "nl": "dutch", "pl": "polish", "ru": "russian", "ko": "koreana", "zh": "schinese"][code] ?? "english"
    }

    public static func parse(_ data: Data, appID: String) -> GameDetails? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any], entry["success"] as? Bool == true,
              let game = entry["data"] as? [String: Any] else { return nil }
        let release = game["release_date"] as? [String: Any]
        let details = GameDetails(
            source: .steam,
            summary: PlainText.from(html: game["short_description"] as? String ?? ""),
            developers: (game["developers"] as? [String] ?? []).map(PlainText.decodeEntities),
            publishers: (game["publishers"] as? [String] ?? []).filter { !$0.isEmpty }.map(PlainText.decodeEntities),
            releaseText: (release?["date"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            genres: (game["genres"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String },
            url: GameLinks.store(steamID: appID),
            hasMacVersion: (game["platforms"] as? [String: Any])?["mac"] as? Bool)
        return details.isEmpty ? nil : details
    }
}

/// TheGamesDB (thegamesdb.net), with the person's API key: found by name on PC or Mac.
public enum TheGamesDB {
    static let api = "https://api.thegamesdb.net"
    public static let pc = 1, mac = 37

    public static func searchURL(title: String, platforms: [Int], key: String) -> URL {
        var c = URLComponents(string: "\(api)/v1.1/Games/ByGameName")!
        c.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "name", value: title),
                        URLQueryItem(name: "filter[platform]", value: platforms.map(String.init).joined(separator: ",")),
                        URLQueryItem(name: "fields", value: "overview,publishers,genres,alternates")]
        return c.url!
    }

    public static func listURL(_ kind: String, key: String) -> URL {
        var c = URLComponents(string: "\(api)/v1/\(kind)")!
        c.queryItems = [URLQueryItem(name: "apikey", value: key)]
        return c.url!
    }

    struct Game {
        var id: Int
        var title: String
        var alternates: [String]
        var platform: Int
        var overview: String
        var released: Date?
        var developers: [Int], publishers: [Int], genres: [Int]
    }

    static func games(in data: Data) -> [Game] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let games = (root["data"] as? [String: Any])?["games"] as? [[String: Any]] else { return [] }
        return games.compactMap { g in
            guard let id = g["id"] as? Int, let title = g["game_title"] as? String else { return nil }
            return Game(id: id, title: title, alternates: g["alternates"] as? [String] ?? [], platform: g["platform"] as? Int ?? 0,
                        overview: g["overview"] as? String ?? "", released: (g["release_date"] as? String).flatMap(day.date(from:)),
                        developers: g["developers"] as? [Int] ?? [], publishers: g["publishers"] as? [Int] ?? [],
                        genres: g["genres"] as? [Int] ?? [])
        }
    }

    /// The same title, else one that starts with it, else the first; on the platform asked first when there's a choice.
    static func bestMatch(_ games: [Game], title: String, platforms: [Int]) -> Game? {
        let wanted = normalized(title)
        let ordered = games.sorted { (platforms.firstIndex(of: $0.platform) ?? 99) < (platforms.firstIndex(of: $1.platform) ?? 99) }
        func titles(_ g: Game) -> [String] { ([g.title] + g.alternates).map(normalized) }
        return ordered.first { titles($0).contains(wanted) }
            ?? ordered.first { titles($0).contains { $0.hasPrefix(wanted) } }
            ?? ordered.first
    }

    static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    /// A /v1/Genres, /v1/Developers or /v1/Publishers answer: { data: { <kind>: { "<id>": { id, name } } } }.
    static func names(in data: Data) -> [Int: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = root["data"] as? [String: Any] else { return [:] }
        var result: [Int: String] = [:]
        for (key, value) in inner where key != "count" {
            for (id, entry) in value as? [String: Any] ?? [:] {
                guard let entry = entry as? [String: Any], let name = entry["name"] as? String else { continue }
                result[(entry["id"] as? Int) ?? Int(id) ?? -1] = name
            }
        }
        return result
    }

    static func details(_ game: Game, names: Names) -> GameDetails {
        GameDetails(source: .theGamesDB, summary: PlainText.paragraphs(game.overview),
                    developers: game.developers.compactMap { names.developers[$0] },
                    publishers: game.publishers.compactMap { names.publishers[$0] },
                    releaseDate: game.released, genres: game.genres.compactMap { names.genres[$0] },
                    url: URL(string: "https://thegamesdb.net/game.php?id=\(game.id)"))
    }

    struct Names: Codable {
        var fetched: Date
        var genres: [Int: String] = [:], developers: [Int: String] = [:], publishers: [Int: String] = [:]
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Store text as plain words.
enum PlainText {
    static func from(html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return paragraphs(decodeEntities(s))
    }

    static func decodeEntities(_ text: String) -> String {
        var s = text
        for (entity, char) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&reg;", "®"), ("&trade;", "™"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s
    }

    /// Lines trimmed, blank runs made one blank line.
    static func paragraphs(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}

/// Details fetched once and kept a month in a folder; offline, the cache answers however old.
public actor GameDetailsCache {
    public typealias Fetch = @Sendable (URLRequest) async throws -> Data

    let folder: URL
    let fetch: Fetch
    let now: @Sendable () -> Date
    private var key: String?
    public static let maxAge: TimeInterval = 30 * 86400
    /// The Steam store answers about 200 requests in 5 minutes: one every 1.5 seconds stays under it.
    let steamSpacing: TimeInterval
    private var nextSteamRequest = Date.distantPast

    public init(folder: URL, key: String? = nil, fetch: @escaping Fetch = CoverCache.download, now: @escaping @Sendable () -> Date = { Date() },
                steamSpacing: TimeInterval = 1.5) {
        self.folder = folder
        self.fetch = fetch
        self.now = now
        self.key = key?.isEmpty == false ? key : nil
        self.steamSpacing = steamSpacing
    }

    /// Waits for the Steam store's next free slot, so fetching a whole library isn't refused.
    private func paceSteam() async {
        guard steamSpacing > 0 else { return }
        let slot = max(Date(), nextSteamRequest)
        nextSteamRequest = slot.addingTimeInterval(steamSpacing)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    }

    /// A new TheGamesDB key can find games that had nothing without one.
    public func setKey(_ key: String?) {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key?.isEmpty == false ? key : nil
    }

    /// Answers saved in a folder (Tests/Fixtures/Details), for tests and snapshots.
    public static func folder(_ folder: URL) -> Fetch {
        { request in
            guard let url = request.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
            let query = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            let name: String
            if url.host() == "store.steampowered.com" {
                name = "steam-\(query["appids"] ?? "").json"
            } else if url.host() == "itunes.apple.com" {
                name = "appstore-\((query["term"] ?? "").lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()).json"
            } else if url.path().hasSuffix("/ByGameName") {
                name = "tgdb-\((query["name"] ?? "").lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()).json"
            } else {
                name = "tgdb-\(url.lastPathComponent).json"
            }
            guard let data = try? Data(contentsOf: folder.appending(path: name)) else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }

    /// A Steam game's details, in a language Steam knows ("french").
    public func details(steamID: String, language: String, force: Bool = false) async -> GameDetails? {
        await cached("steam2-\(steamID)-\(language)", force: force) { [fetch] in
            await self.paceSteam()
            let data = try await fetch(URLRequest(url: SteamDetails.url(appID: steamID, language: language), timeoutInterval: 15))
            return SteamDetails.parse(data, appID: steamID)
        }
    }

    /// Another game's details from TheGamesDB, by its title. Nil without a key.
    public func details(title: String, mac: Bool, force: Bool = false) async -> GameDetails? {
        guard let key else { return nil }
        let platforms = mac ? [TheGamesDB.mac, TheGamesDB.pc] : [TheGamesDB.pc]
        let name = TheGamesDB.normalized(title)
        return await cached("tgdb-\(name)-\(mac ? "mac" : "pc")", force: force) { [fetch] in
            let data = try await fetch(URLRequest(url: TheGamesDB.searchURL(title: title, platforms: platforms, key: key), timeoutInterval: 15))
            guard let game = TheGamesDB.bestMatch(TheGamesDB.games(in: data), title: title, platforms: platforms) else { return nil }
            return TheGamesDB.details(game, names: await self.names(for: game, key: key))
        }
    }

    /// The game on the Mac App Store, by its title in the person's country: only an app of the same name.
    public func appStore(title: String, country: String, force: Bool = false) async -> MacAppStore.App? {
        let url = folder.appending(path: "appstore-\(TheGamesDB.normalized(title).map { $0 == "/" ? "_" : String($0) }.joined())-\(country).json")
        return await WebCacheFile<MacAppStore.App>(url: url, maxAge: Self.maxAge).value(now: now(), force: force) { [fetch] in
            let data = try await fetch(URLRequest(url: MacAppStore.searchURL(title: title, country: country), timeoutInterval: 15))
            return MacAppStore.match(MacAppStore.apps(in: data), title: title)
        }
    }

    private func cached(_ name: String, force: Bool, find: @Sendable () async throws -> GameDetails?) async -> GameDetails? {
        let url = folder.appending(path: name.map { $0 == "/" ? "_" : String($0) }.joined() + ".json")
        return await WebCacheFile<GameDetails>(url: url, maxAge: Self.maxAge).value(now: now(), force: force, fetch: find)
    }

    /// TheGamesDB's genre, developer and publisher names: three lists, fetched at most once a month,
    /// or again after a day when a game names one they don't have.
    func names(for game: TheGamesDB.Game, key: String) async -> TheGamesDB.Names {
        let url = folder.appending(path: "tgdb-names.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? CompatibilityCache.decoder.decode(TheGamesDB.Names.self, from: $0) }
        if let stored {
            let age = now().timeIntervalSince(stored.fetched)
            let covers = game.genres.allSatisfy { stored.genres[$0] != nil } && game.developers.allSatisfy { stored.developers[$0] != nil }
                && game.publishers.allSatisfy { stored.publishers[$0] != nil }
            if age < Self.maxAge && (covers || age < 86400) { return stored }
        }
        do {
            async let genres = fetch(URLRequest(url: TheGamesDB.listURL("Genres", key: key), timeoutInterval: 30))
            async let developers = fetch(URLRequest(url: TheGamesDB.listURL("Developers", key: key), timeoutInterval: 30))
            async let publishers = fetch(URLRequest(url: TheGamesDB.listURL("Publishers", key: key), timeoutInterval: 30))
            let names = TheGamesDB.Names(fetched: now(), genres: TheGamesDB.names(in: try await genres),
                                         developers: TheGamesDB.names(in: try await developers), publishers: TheGamesDB.names(in: try await publishers))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? CompatibilityCache.encoder.encode(names).write(to: url, options: .atomic)
            return names
        } catch {
            return stored ?? TheGamesDB.Names(fetched: .distantPast)
        }
    }
}
