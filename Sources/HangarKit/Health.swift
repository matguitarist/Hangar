import Foundation

/// Something in the library that needs the person (S-042), each with its own fix.
public enum HealthIssue: Hashable, Sendable, Identifiable {
    /// The game's files aren't where Hangar last saw them. Fix: Locate…
    case filesMoved(gameID: String)
    /// Hangar can't read the bottle. Fix: Open in CrossOver.
    case bottleUnreadable(bottle: String)
    /// Steam in the bottle is signed out, and Steam games run there. Fix: Open Steam.
    case signedOut(bottle: String)
    /// The game has saves on this Mac and no backup. Fix: Back Up Now.
    case neverBackedUp(gameID: String)

    public enum Kind: Int, CaseIterable, Sendable, Comparable {
        case filesMoved, bottleUnreadable, signedOut, neverBackedUp
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public var kind: Kind {
        switch self {
        case .filesMoved: .filesMoved
        case .bottleUnreadable: .bottleUnreadable
        case .signedOut: .signedOut
        case .neverBackedUp: .neverBackedUp
        }
    }

    public var id: String {
        switch self {
        case let .filesMoved(id): "moved:" + id
        case let .bottleUnreadable(b): "unreadable:" + b
        case let .signedOut(b): "signedOut:" + b
        case let .neverBackedUp(id): "backup:" + id
        }
    }
}

/// What Hangar knows about the library, as plain values the rules read.
public struct HealthFacts: Sendable {
    public var games: [Game]
    public var missingFiles: Set<String>
    public var unreadableBottles: [String]
    public var signedOutBottles: Set<String>
    /// Games with saves found on this Mac.
    public var gamesWithSaves: Set<String>
    /// Games with at least one save backup.
    public var gamesWithBackups: Set<String>

    public init(games: [Game], missingFiles: Set<String> = [], unreadableBottles: [String] = [], signedOutBottles: Set<String> = [],
                gamesWithSaves: Set<String> = [], gamesWithBackups: Set<String> = []) {
        self.games = games
        self.missingFiles = missingFiles
        self.unreadableBottles = unreadableBottles
        self.signedOutBottles = signedOutBottles
        self.gamesWithSaves = gamesWithSaves
        self.gamesWithBackups = gamesWithBackups
    }
}

public enum LibraryHealth {
    /// Every issue, grouped by kind, then by name.
    public static func issues(_ facts: HealthFacts) -> [HealthIssue] {
        var list: [HealthIssue] = []
        let titles = Dictionary(facts.games.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        for game in facts.games where facts.missingFiles.contains(game.id) {
            list.append(.filesMoved(gameID: game.id))
        }
        list += facts.unreadableBottles.sorted().map { .bottleUnreadable(bottle: $0) }
        let steamBottles = Set(facts.games.filter { $0.steamID != nil }.compactMap(\.bottle))
        list += facts.signedOutBottles.intersection(steamBottles).sorted().map { .signedOut(bottle: $0) }
        for game in facts.games where facts.gamesWithSaves.contains(game.id) && !facts.gamesWithBackups.contains(game.id)
            && !facts.missingFiles.contains(game.id) {
            list.append(.neverBackedUp(gameID: game.id))
        }
        return list.sorted { a, b in
            a.kind != b.kind ? a.kind < b.kind : (name(a, titles), a.id) < (name(b, titles), b.id)
        }
    }

    static func name(_ issue: HealthIssue, _ titles: [String: String]) -> String {
        switch issue {
        case let .filesMoved(id), let .neverBackedUp(id): titles[id] ?? id
        case let .bottleUnreadable(b), let .signedOut(b): b
        }
    }
}
