import Foundation

/// Finds games by part of their name: words in any order ("knight hollow"), and initials ("bg3").
public enum GameSearch {
    public static func matches(_ query: String, title: String) -> Bool {
        let tokens = words(query)
        guard !tokens.isEmpty else { return true }
        let titleWords = words(title)
        let joined = titleWords.joined()
        let initials = String(titleWords.compactMap(\.first))
        return tokens.allSatisfy { token in
            titleWords.contains { $0.hasPrefix(token) } || joined.contains(token) || initials.contains(token)
        }
    }

    /// Lowercased words without accents or punctuation; "Baldur's" is one word, "baldurs".
    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

public enum GameSort: String, Sendable, CaseIterable {
    case name, recentlyPlayed, playtime

    public func sorted(_ games: [Game]) -> [Game] {
        let byName: (Game, Game) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        switch self {
        case .name:
            return games.sorted(by: byName)
        case .recentlyPlayed:
            return games.sorted { a, b in
                switch (a.lastPlayed, b.lastPlayed) {
                case let (x?, y?): x == y ? byName(a, b) : x > y
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): byName(a, b)
                }
            }
        case .playtime:
            return games.sorted { $0.playtime == $1.playtime ? byName($0, $1) : $0.playtime > $1.playtime }
        }
    }
}

/// "3 h 20 min", "45 min", in English and French alike.
public enum PlaytimeText {
    public static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, seconds > 0 ? 1 : 0)) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }
}
