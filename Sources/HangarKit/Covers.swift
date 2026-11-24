import Foundation

/// Cover art, fetched once and kept in a cover folder. Offline, the cache answers; with no
/// cache either, the caller draws a generated cover. Sources, ported from Attic:
/// - the Steam store's library art (IStoreBrowseService/GetItems), no key needed; newer games
///   name their files by hash, so the URL can't be guessed;
/// - SteamGridDB (steamgriddb.com) with the person's free API key: for a Steam game the store
///   has no portrait art for, and, by name, for Windows games that aren't on Steam.
public actor CoverCache {
    public typealias Fetch = @Sendable (URLRequest) async throws -> Data

    let folder: URL
    let fetch: Fetch
    /// The SteamGridDB API key, or nil.
    private var gridKey: String?
    /// Covers that failed this run, so a missing image isn't asked for again and again.
    private var failed = Set<String>()
    private var inFlight: [String: Task<URL?, Never>] = [:]

    public init(folder: URL, gridKey: String? = nil, fetch: @escaping Fetch = CoverCache.download) {
        self.folder = folder
        self.gridKey = gridKey
        self.fetch = fetch
    }

    /// A new key can find covers that failed without one.
    public func setGridKey(_ key: String?) {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        gridKey = key?.isEmpty == false ? key : nil
        failed.removeAll()
    }

    public func cachedFile(steamID: String) -> URL { folder.appending(path: "steam-\(steamID).jpg") }

    public func cachedFile(title: String) -> URL {
        let name = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return folder.appending(path: "grid-\(name).jpg")
    }

    /// The cover file for a Steam game, downloading it the first time. Nil when there is none.
    public func cover(steamID: String) async -> URL? {
        let fetch = self.fetch
        let gridKey = self.gridKey
        return await cached(key: "steam:\(steamID)", file: cachedFile(steamID: steamID)) {
            if let url = await SteamArt.coverURL(appID: steamID, fetch: fetch) { return url }
            guard let gridKey else { return nil }
            return await SteamGridDB.coverURL(steamID: steamID, apiKey: gridKey, fetch: fetch)
        }
    }

    /// The cover for a game that isn't on Steam, found on SteamGridDB by its name. Needs a key.
    public func cover(title: String) async -> URL? {
        guard let gridKey else { return nil }
        let fetch = self.fetch
        return await cached(key: "title:\(title)", file: cachedFile(title: title)) {
            await SteamGridDB.coverURL(title: title, apiKey: gridKey, fetch: fetch)
        }
    }

    private func cached(key: String, file: URL, find: @escaping @Sendable () async -> URL?) async -> URL? {
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if failed.contains(key) { return nil }
        if let running = inFlight[key] { return await running.value }
        let fetch = self.fetch
        let folder = self.folder
        let task = Task<URL?, Never> {
            guard let url = await find(), let data = try? await fetch(URLRequest(url: url, timeoutInterval: 15)),
                  data.count > 1024 else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (try? data.write(to: file, options: .atomic)) != nil ? file : nil
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if result == nil { failed.insert(key) }
        return result
    }

    @Sendable
    public static func download(_ request: URLRequest) async throws -> Data {
        var request = request
        // A firewall that holds the connection (LuLu waiting on an answer) must not leave covers waiting forever.
        if request.timeoutInterval > 15 { request.timeoutInterval = 15 }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

/// The Steam store's library art, from Attic's SteamStore.
public enum SteamArt {
    /// The portrait cover's URL: the store's asset list, else the old fixed file name.
    public static func coverURL(appID: String, fetch: CoverCache.Fetch) async -> URL? {
        if let data = try? await fetch(URLRequest(url: assetsURL(appID: appID), timeoutInterval: 15)),
           let cover = assets(from: data).cover {
            return cover
        }
        // Older games keep their art under fixed names; check it exists before using it.
        let classic = URL(string: "https://shared.steamstatic.com/store_item_assets/steam/apps/\(appID)/library_600x900_2x.jpg")!
        var head = URLRequest(url: classic, timeoutInterval: 15)
        head.httpMethod = "HEAD"
        return (try? await fetch(head)) != nil ? classic : nil
    }

    static func assetsURL(appID: String) -> URL {
        let request = #"{"ids":[{"appid":\#(appID)}],"context":{"language":"english","country_code":"US"},"data_request":{"include_assets":true}}"#
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1")!
        components.queryItems = [URLQueryItem(name: "input_json", value: request)]
        return components.url!
    }

    /// GetItems' asset file names, put into its URL format.
    static func assets(from data: Data) -> (cover: URL?, hero: URL?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = ((root["response"] as? [String: Any])?["store_items"] as? [[String: Any]])?.first,
              let assets = item["assets"] as? [String: Any],
              let format = assets["asset_url_format"] as? String else { return (nil, nil) }
        func url(_ keys: String...) -> URL? {
            for key in keys {
                guard let name = assets[key] as? String, !name.isEmpty else { continue }
                return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/"
                    + format.replacingOccurrences(of: "${FILENAME}", with: name))
            }
            return nil
        }
        return (url("library_capsule_2x", "library_capsule"), url("library_hero_2x", "library_hero"))
    }
}

/// Community art from SteamGridDB, from Attic's SteamGridDB, plus a search by name.
public enum SteamGridDB {
    static let api = "https://www.steamgriddb.com/api/v2"

    public static func coverURL(steamID: String, apiKey: String, fetch: CoverCache.Fetch) async -> URL? {
        guard let data = try? await fetch(request("\(api)/grids/steam/\(steamID)", query: coverQuery, key: apiKey)) else { return nil }
        return firstURL(in: data)
    }

    /// The best match for a name, then its best-rated portrait cover.
    public static func coverURL(title: String, apiKey: String, fetch: CoverCache.Fetch) async -> URL? {
        let term = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? title
        guard let found = try? await fetch(request("\(api)/search/autocomplete/\(term)", query: [], key: apiKey)),
              let id = firstGameID(in: found),
              let data = try? await fetch(request("\(api)/grids/game/\(id)", query: coverQuery, key: apiKey)) else { return nil }
        return firstURL(in: data)
    }

    static let coverQuery = [URLQueryItem(name: "types", value: "static"), URLQueryItem(name: "nsfw", value: "false"),
                             URLQueryItem(name: "dimensions", value: "600x900,342x482,660x930")]

    static func request(_ address: String, query: [URLQueryItem], key: String) -> URLRequest {
        var components = URLComponents(string: address)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The first picture of a { "success": true, "data": [ { "url": … } ] } answer, best-rated first.
    static func firstURL(in data: Data) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool == true,
              let pictures = root["data"] as? [[String: Any]] else { return nil }
        return pictures.lazy.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
    }

    static func firstGameID(in data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool == true,
              let games = root["data"] as? [[String: Any]] else { return nil }
        return games.first?["id"] as? Int
    }
}

/// A generated cover's hue, the same for a title every time.
public enum GeneratedCover {
    public static func hue(for title: String) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in title.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Double(hash % 360) / 360
    }
}
