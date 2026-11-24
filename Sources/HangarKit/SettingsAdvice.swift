import Foundation

/// What PCGamingWiki's {{API}} box says about a Windows game: its Direct3D versions and builds.
public struct GameAPI: Codable, Sendable, Equatable {
    public var direct3D: [Int]
    public var windows64: Bool?
    public var windows32: Bool?

    public init(direct3D: [Int], windows64: Bool? = nil, windows32: Bool? = nil) {
        self.direct3D = direct3D
        self.windows64 = windows64
        self.windows32 = windows32
    }

    /// The {{API}} box of a page source; nil when it says nothing useful.
    static func parse(_ source: String) -> GameAPI? {
        guard let start = source.range(of: "{{API", options: .caseInsensitive),
              let end = GameData.closingBraces(in: source[...], from: start.upperBound) else { return nil }
        var values: [String: String] = [:]
        for part in Compatibility.splitTopLevel(String(source[start.upperBound..<end])) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            values[part[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                part[part.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        // "9.0c, 11" → [9, 11]: the whole number before each dot.
        let versions = (values["direct3d versions"] ?? "").split(whereSeparator: { ",;/ ".contains($0) })
            .compactMap { Int($0.split(separator: ".").first ?? "") }
            .filter { (1...12).contains($0) }
        func flag(_ key: String) -> Bool? {
            switch values[key] { case "true": true; case "false": false; default: nil }
        }
        let api = GameAPI(direct3D: Array(Set(versions)).sorted(), windows64: flag("windows 64-bit exe"), windows32: flag("windows 32-bit exe"))
        return api.direct3D.isEmpty && api.windows64 == nil && api.windows32 == nil ? nil : api
    }
}

/// A setting to change in a game's bottle, and why (S-034).
public struct SettingsSuggestion: Sendable, Equatable, Identifiable {
    public enum Change: Sendable, Equatable {
        case graphics(GraphicsBackend)
        case msync, avx, highResolution
    }

    public enum Reason: Sendable, Equatable {
        /// A sentence of AppleGamingWiki's CrossOver notes.
        case wikiNote(String)
        /// PCGamingWiki's highest Direct3D version.
        case directX(Int)
    }

    public var change: Change
    public var reason: Reason

    public var id: String {
        switch change {
        case let .graphics(backend): "graphics-\(backend.rawValue)"
        case .msync: "msync"
        case .avx: "avx"
        case .highResolution: "highResolution"
        }
    }

    public func applied(to settings: BottleSettings) -> BottleSettings {
        var s = settings
        switch change {
        case let .graphics(backend): s.graphics = backend
        case .msync: s.msync = true
        case .avx: s.avx = true
        case .highResolution: s.highResolution = true
        }
        return s
    }
}

public enum SettingsAdvice {
    /// Words that turn a sentence into a warning: "DXVK crashes", "doesn't work with DXMT".
    static let warnings = ["crash", "doesn't", "does not", "don't", "do not", "not ", "n't ", "black", "broken", "fail", "without",
                           "instead of", "avoid", "freez", "hang", "glitch", "error", "unplayable", "won't"]

    /// The settings to suggest for a bottle, best first: what the wiki's notes recommend, then a rule
    /// from the game's Direct3D version. Only changes from the current settings; never "Auto already does this".
    public static func suggestions(current: BottleSettings, crossOverNotes: String?, api: GameAPI?) -> [SettingsSuggestion] {
        var found: [SettingsSuggestion] = []
        var backends: [(GraphicsBackend, String)] = []
        for sentence in sentences(crossOverNotes ?? "") {
            let lower = sentence.lowercased()
            guard !warnings.contains(where: lower.contains) else { continue }
            for backend in [GraphicsBackend.d3dMetal, .dxmt, .dxvk, .wined3d] where lower.contains(backend.rawValue) {
                backends.append((backend, sentence))
            }
            for (word, change) in [("msync", SettingsSuggestion.Change.msync), ("avx", .avx), ("high resolution", .highResolution), ("retina", .highResolution)]
            where lower.contains(word) && !found.contains(where: { $0.change == change }) {
                found.append(SettingsSuggestion(change: change, reason: .wikiNote(sentence)))
            }
        }
        // The notes name one backend: that one. Several: they disagree, so no graphics advice from them.
        if Set(backends.map(\.0)).count == 1, let (backend, sentence) = backends.first {
            found.insert(SettingsSuggestion(change: .graphics(backend), reason: .wikiNote(sentence)), at: 0)
        } else if backends.isEmpty, let version = api?.direct3D.max(), let backend = backend(forDirectX: version) {
            found.insert(SettingsSuggestion(change: .graphics(backend), reason: .directX(version)), at: 0)
        }
        return found.filter { $0.applied(to: current) != current }
    }

    /// CrossOver's Auto picks D3DMetal, which runs Direct3D 11 and 12: nothing to suggest there.
    /// DXMT runs Direct3D 10 (and 11); DXVK runs 9 and older best.
    static func backend(forDirectX version: Int) -> GraphicsBackend? {
        switch version {
        case 10: .dxmt
        case ...9: .dxvk
        default: nil
        }
    }

    static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: "; ", with: ". ").components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty }
            .map { $0.count > 140 ? String($0.prefix(139)) + "…" : $0 }
    }
}
