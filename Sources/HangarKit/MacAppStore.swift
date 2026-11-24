import Foundation

/// The Mac App Store, through Apple's public search (no key): is there a Mac app of this game?
public enum MacAppStore {
    public struct App: Codable, Sendable, Equatable {
        public var name: String
        public var url: URL
        public var bundleID: String?

        public init(name: String, url: URL, bundleID: String? = nil) {
            self.name = name
            self.url = url
            self.bundleID = bundleID
        }
    }

    /// Mac apps named like the title, in a country's store ("ca", "fr", "us").
    public static func searchURL(title: String, country: String) -> URL {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: title), URLQueryItem(name: "entity", value: "macSoftware"),
                        URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "country", value: country)]
        return c.url!
    }

    /// The person's store country, from their region; the US store when it can't tell.
    public static func country(_ region: String?) -> String {
        guard let region, region.count == 2 else { return "us" }
        return region.lowercased()
    }

    static func apps(in data: Data) -> [App] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard r["kind"] as? String == "mac-software", let name = r["trackName"] as? String,
                  let link = r["trackViewUrl"] as? String, var c = URLComponents(string: link) else { return nil }
            c.queryItems = (c.queryItems ?? []).filter { $0.name != "uo" }
            if c.queryItems?.isEmpty == true { c.queryItems = nil }
            guard let url = c.url else { return nil }
            return App(name: name, url: url, bundleID: r["bundleId"] as? String)
        }
    }

    /// Only an app with the same name, apart from capitals and punctuation: a search for "Blue Prince"
    /// also lists other apps, and those aren't this game.
    public static func match(_ apps: [App], title: String) -> App? {
        apps.first { AppleGamingWiki.sameGame($0.name, title) }
    }
}
