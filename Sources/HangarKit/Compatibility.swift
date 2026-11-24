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

    /// "#REDIRECT [[Other page]]" → "Other_page".
    static func redirect(_ source: String) -> String? {
        guard source.uppercased().hasPrefix("#REDIRECT"), let open = source.range(of: "[["),
              let close = source.range(of: "]]", range: open.upperBound..<source.endIndex) else { return nil }
        return pageName(String(source[open.upperBound..<close.lowerBound]))
    }
}

/// AppleGamingWiki's verdicts, cached in a folder: used offline, asked again at most once a week.
public actor CompatibilityCache {
    /// Fetches a page's source, or nil when the wiki has no such page. Throws when offline.
    public typealias Fetch = @Sendable (String) async throws -> String?

    let folder: URL
    let fetch: Fetch
    let now: @Sendable () -> Date
    public static let maxAge: TimeInterval = 7 * 86400

    public init(folder: URL, fetch: @escaping Fetch = CompatibilityCache.network, now: @escaping @Sendable () -> Date = { Date() }) {
        self.folder = folder
        self.fetch = fetch
        self.now = now
    }

    /// The live wiki.
    public static let network: Fetch = { page in
        var request = URLRequest(url: AppleGamingWiki.rawURL(page), timeoutInterval: 15)
        request.setValue("Hangar (macOS game library)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
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
        await WebCacheFile<Compatibility>(url: file(title), maxAge: Self.maxAge).value(now: now()) {
            var page = AppleGamingWiki.pageName(title)
            var source = try await fetch(page)
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
