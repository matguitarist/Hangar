import Foundation

/// Steam cover art, fetched once and kept in a cache folder. Offline, the cache answers;
/// with no cache either, the caller draws a generated cover.
public actor CoverCache {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    let folder: URL
    let fetch: Fetch
    /// Ids that failed this run, so a missing image isn't asked for again and again.
    private var failed = Set<String>()
    private var inFlight: [String: Task<URL?, Never>] = [:]

    public init(folder: URL, fetch: @escaping Fetch = CoverCache.download) {
        self.folder = folder
        self.fetch = fetch
    }

    /// Steam's portrait library art for an app id.
    public static func steamURLs(_ id: String) -> [URL] {
        ["https://shared.steamstatic.com/store_item_assets/steam/apps/\(id)/library_600x900_2x.jpg",
         "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_600x900_2x.jpg"].compactMap(URL.init(string:))
    }

    public func cachedFile(steamID: String) -> URL {
        folder.appending(path: "steam-\(steamID).jpg")
    }

    /// The cover file for a Steam game, downloading it the first time. Nil when there is none.
    public func cover(steamID: String) async -> URL? {
        let file = cachedFile(steamID: steamID)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if failed.contains(steamID) { return nil }
        if let running = inFlight[steamID] { return await running.value }
        let urls = Self.steamURLs(steamID)
        let fetch = self.fetch
        let folder = self.folder
        let task = Task<URL?, Never> {
            for url in urls {
                guard let data = try? await fetch(url), data.count > 1024 else { continue }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
                return file
            }
            return nil
        }
        inFlight[steamID] = task
        let result = await task.value
        inFlight[steamID] = nil
        if result == nil { failed.insert(steamID) }
        return result
    }

    @Sendable
    public static func download(_ url: URL) async throws -> Data {
        // A firewall that holds the connection (LuLu waiting on an answer) must not leave covers waiting forever.
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.fileDoesNotExist) }
        return data
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
