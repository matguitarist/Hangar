import Foundation

/// How well a game runs on a Mac for each method, from AppleGamingWiki's Compatibility/macOS template.
public struct Compatibility: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable, CaseIterable {
        case native, rosetta = "rosetta 2", crossOver = "crossover", wine, parallels

        public var title: String {
            switch self {
            case .native: String(localized: "Native", bundle: .main)
            case .rosetta: "Rosetta 2"
            case .crossOver: "CrossOver"
            case .wine: "Wine"
            case .parallels: "Parallels"
            }
        }
    }

    public enum Rating: String, Codable, Sendable {
        case perfect, playable, runs, unplayable, unknown

        public var title: String {
            switch self {
            case .perfect: String(localized: "Perfect", bundle: .main)
            case .playable: String(localized: "Playable", bundle: .main)
            case .runs: String(localized: "Runs", bundle: .main)
            case .unplayable: String(localized: "Doesn't run", bundle: .main)
            case .unknown: String(localized: "Not tested", bundle: .main)
            }
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var method: Method
        public var rating: Rating
        public var notes: String
    }

    /// The wiki page the data came from ("Hollow_Knight").
    public var page: String
    public var entries: [Entry]

    public var url: URL { AppleGamingWiki.pageURL(page) }

    /// Reads the template from a page's source. Methods marked "na" (not available) are left out.
    public static func parse(_ source: String, page: String) -> Compatibility? {
        guard let start = source.range(of: "{{Compatibility/macOS") else { return nil }
        var depth = 0
        var end = source.endIndex
        var i = start.lowerBound
        while i < source.endIndex {
            if source[i...].hasPrefix("{{") { depth += 1; i = source.index(i, offsetBy: 2); continue }
            if source[i...].hasPrefix("}}") {
                depth -= 1
                i = source.index(i, offsetBy: 2)
                if depth == 0 { end = i; break }
                continue
            }
            i = source.index(after: i)
        }
        var values: [String: String] = [:]
        for part in splitTopLevel(String(source[start.upperBound..<end].dropLast(2))) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            values[key] = String(part[part.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let entries: [Entry] = Method.allCases.compactMap { method in
            guard let value = values[method.rawValue]?.lowercased(), value != "na", !value.isEmpty else { return nil }
            return Entry(method: method, rating: Rating(rawValue: value) ?? .unknown, notes: plainText(values["\(method.rawValue) notes"] ?? ""))
        }
        return Compatibility(page: page, entries: entries)
    }

    /// The template's |key = value parts, ignoring the bars inside {{…}} and [[…]].
    static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if (c == "{" && next == "{") || (c == "[" && next == "[") { depth += 1; current += String([c, next!]); i += 2; continue }
            if (c == "}" && next == "}") || (c == "]" && next == "]") { depth -= 1; current += String([c, next!]); i += 2; continue }
            if c == "|" && depth == 0 { parts.append(current); current = ""; i += 1; continue }
            current.append(c)
            i += 1
        }
        parts.append(current)
        chars = []
        return parts
    }

    /// Wiki markup as plain words: references and templates out, [[Page|words]] → words, '''bold''' → bold.
    static func plainText(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"<ref[^>]*/>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<ref[^>]*>[\s\S]*?</ref>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[https?://\S+ ([^\]]*)\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "'''", with: "").replacingOccurrences(of: "''", with: "")
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

public enum AppleGamingWiki {
    /// A page title as the wiki writes it: spaces become underscores.
    public static func pageName(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
    }

    public static func pageURL(_ page: String) -> URL {
        let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) ?? page
        return URL(string: "https://www.applegamingwiki.com/wiki/\(encoded)")!
    }

    static func rawURL(_ page: String) -> URL {
        var c = URLComponents(string: "https://www.applegamingwiki.com/w/index.php")!
        c.queryItems = [URLQueryItem(name: "title", value: page), URLQueryItem(name: "action", value: "raw")]
        return c.url!
    }

    /// What the wiki's answer means: the page's source, nil when the wiki itself says it has no such page
    /// (a 404 in wiki text), or an error for anything else. The site sometimes answers with its own
    /// "Page Not Found" web page for pages that exist; that must not be kept as "no page".
    static func source(status: Int, contentType: String?, data: Data) throws -> String? {
        let type = contentType?.lowercased() ?? ""
        switch status {
        case 200 where !type.contains("text/html"): return String(decoding: data, as: UTF8.self)
        case 404 where type.contains("text/x-wiki"): return nil
        default: throw URLError(.badServerResponse)
        }
    }

    /// The wiki's title search (opensearch), for a game whose page is written differently.
    static func searchURL(_ title: String) -> URL {
        var c = URLComponents(string: "https://www.applegamingwiki.com/w/api.php")!
        c.queryItems = [URLQueryItem(name: "action", value: "opensearch"), URLQueryItem(name: "format", value: "json"),
                        URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "redirects", value: "resolve"),
                        URLQueryItem(name: "search", value: title)]
        return c.url!
    }

    /// The titles in an opensearch answer: ["query", [titles], [descriptions], [urls]].
    static func titles(fromSearch data: Data) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any], array.count > 1 else { return [] }
        return array[1] as? [String] ?? []
    }

    /// The same name apart from capitals, accents, punctuation and spaces: "DRAGON QUEST XI S: …" is "Dragon Quest XI S …",
    /// but "Diablo II Resurrected" isn't "Diablo II".
    public static func sameGame(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String {
            String(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars
                .filter(CharacterSet.alphanumerics.contains).map(Character.init))
        }
        return !key(a).isEmpty && key(a) == key(b)
    }

    /// "#REDIRECT [[Other page]]" → "Other_page".
    static func redirect(_ source: String) -> String? {
        guard source.uppercased().hasPrefix("#REDIRECT"), let open = source.range(of: "[["),
              let close = source.range(of: "]]", range: open.upperBound..<source.endIndex) else { return nil }
        return pageName(String(source[open.upperBound..<close.lowerBound]))
    }
}

/// AppleGamingWiki's verdicts, cached in a folder: used offline, asked again at most once a week
/// (a game with no page, the next day).
public actor CompatibilityCache {
    /// Fetches a page's source, or nil when the wiki has no such page. Throws when offline.
    public typealias Fetch = @Sendable (String) async throws -> String?
    /// The wiki's page titles for a search.
    public typealias Search = @Sendable (String) async throws -> [String]

    let folder: URL
    let fetch: Fetch
    let search: Search
    let now: @Sendable () -> Date
    public static let maxAge: TimeInterval = 7 * 86400

    public init(folder: URL, fetch: @escaping Fetch = CompatibilityCache.network, search: @escaping Search = { _ in [] },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.folder = folder
        self.fetch = fetch
        self.search = search
        self.now = now
    }

    /// The live wiki.
    public static let network: Fetch = { page in
        var request = URLRequest(url: AppleGamingWiki.rawURL(page), timeoutInterval: 15)
        request.setValue("Hangar (macOS game library)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return try AppleGamingWiki.source(status: http?.statusCode ?? 0, contentType: http?.value(forHTTPHeaderField: "Content-Type"), data: data)
    }

    /// The live wiki's title search.
    public static let networkSearch: Search = { title in
        var request = URLRequest(url: AppleGamingWiki.searchURL(title), timeoutInterval: 15)
        request.setValue("Hangar (macOS game library)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return AppleGamingWiki.titles(fromSearch: data)
    }

    /// Page sources in a folder (Tests/Fixtures/AppleGamingWiki), for tests and snapshots.
    public static func folder(_ folder: URL) -> Fetch {
        { page in try? String(contentsOf: folder.appending(path: "\(page).txt"), encoding: .utf8) }
    }

    func file(_ title: String) -> URL {
        folder.appending(path: AppleGamingWiki.pageName(title).replacingOccurrences(of: "/", with: "_") + ".json")
    }

    /// The verdicts for a game, by its title. Nil when the wiki has no page for it, or offline with nothing cached.
    public func compatibility(for title: String) async -> Compatibility? {
        await WebCacheFile<Compatibility>(url: file(title), maxAge: Self.maxAge).value(now: now()) { [search] in
            var page = AppleGamingWiki.pageName(title)
            var source = try await fetch(page)
            // Not under its exact name: the wiki's search, only for the same name written differently.
            if source == nil, let match = (try? await search(title))?.first(where: { AppleGamingWiki.sameGame($0, title) }),
               AppleGamingWiki.pageName(match) != page {
                page = AppleGamingWiki.pageName(match)
                source = try await fetch(page)
            }
            if let s = source, let target = AppleGamingWiki.redirect(s) {
                page = target
                source = try await fetch(page)
            }
            return source.flatMap { Compatibility.parse($0, page: page) }
        }
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
