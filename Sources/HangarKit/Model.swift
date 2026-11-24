import Foundation

/// Where Hangar found a game.
public enum GameSource: String, Codable, Sendable, CaseIterable {
    case steam, crossOver, macApp, addedByHand
}

/// A game in the library: a Mac app, a Steam game, or a Windows program in a bottle.
public struct Game: Codable, Sendable, Identifiable, Hashable {
    /// Stable across scans: the source and the store id or path.
    public var id: String
    public var title: String
    public var source: GameSource

    public init(id: String, title: String, source: GameSource) {
        self.id = id
        self.title = title
        self.source = source
    }
}
