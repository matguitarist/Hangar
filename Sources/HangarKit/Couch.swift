import Foundation

/// A move in couch mode, from the arrow keys, a D-pad or a stick (S-028, S-029).
public enum CouchDirection: Sendable, Hashable, CaseIterable {
    case up, down, left, right
}

/// The selection in couch mode: rows of game ids ("Continue Playing", "All Games"), one selected.
/// Left and right move in a row; up and down change rows and keep the column as close as it can.
public struct CouchNavigator: Sendable, Equatable {
    public private(set) var rows: [[String]]
    public private(set) var row = 0
    public private(set) var column = 0

    public init(rows: [[String]]) {
        self.rows = rows.filter { !$0.isEmpty }
    }

    public var selected: String? {
        rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : nil
    }

    public mutating func move(_ direction: CouchDirection) {
        guard !rows.isEmpty else { return }
        switch direction {
        case .left: column = max(column - 1, 0)
        case .right: column = min(column + 1, rows[row].count - 1)
        case .up:
            guard row > 0 else { return }
            row -= 1
            column = min(column, rows[row].count - 1)
        case .down:
            guard row < rows.count - 1 else { return }
            row += 1
            column = min(column, rows[row].count - 1)
        }
    }

    /// Selects a game where it first shows.
    public mutating func select(_ id: String) {
        for (r, ids) in rows.enumerated() {
            if let c = ids.firstIndex(of: id) { row = r; column = c; return }
        }
    }

    /// New rows (a game finished, a scan ended): the same game stays selected when it's still there.
    public mutating func update(rows new: [[String]]) {
        let keep = selected
        rows = new.filter { !$0.isEmpty }
        row = min(row, max(rows.count - 1, 0))
        column = rows.indices.contains(row) ? min(column, max(rows[row].count - 1, 0)) : 0
        if let keep { select(keep) }
    }

    /// The rows couch mode shows: up to ten games played, most recent first, then every game by name.
    public static func rows(for games: [Game], recent limit: Int = 10) -> [[String]] {
        let recent = games.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(limit).map(\.id)
        let all = games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map(\.id)
        return [Array(recent), all]
    }
}
