import Foundation

/// A library written to a file (S-046): games with what the person did, collections, and the covers they chose.
public struct LibraryExport: Codable, Sendable {
    public static let fileExtension = "hangarlibrary"
    public var version = 1
    public var exported: Date
    public var games: [Game]
    public var removed: [Game]
    public var collections: [GameCollection]
    /// Chosen covers, by the file name the games point to.
    public var covers: [String: Data]

    public init(library: LibraryFile, exported: Date = Date()) {
        self.exported = exported
        games = library.games
        removed = library.removed
        collections = library.collections
        var covers: [String: Data] = [:]
        for game in library.games + library.removed {
            guard let path = game.customCover, let data = FileManager.default.contents(atPath: path) else { continue }
            covers[URL(fileURLWithPath: path).lastPathComponent] = data
        }
        self.covers = covers
        // Paths on this Mac mean nothing elsewhere: the covers travel by name.
        self.games = games.map(Self.portable)
        self.removed = removed.map(Self.portable)
    }

    static func portable(_ game: Game) -> Game {
        var game = game
        game.customCover = game.customCover.map { URL(fileURLWithPath: $0).lastPathComponent }
        return game
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryExport.self, from: data)
    }
}

/// What an import changed: "Imported 42 games and 3 collections."
public struct ImportSummary: Sendable, Equatable {
    public var games: Int
    public var collections: Int
}

extension LibraryFile {
    /// Merges an export by game id. Playtime keeps the higher value; collections join by name; settings and
    /// covers come from the file only where the game has none; games not on this Mac go to Removed Games.
    /// `coversFolder` is where the file's covers are written.
    @discardableResult
    public mutating func importing(_ export: LibraryExport, coversFolder: URL) -> ImportSummary {
        var count = 0
        for incoming in export.games + export.removed {
            let cover = incoming.customCover.flatMap { name -> String? in
                guard let data = export.covers[name] else { return nil }
                let target = coversFolder.appending(path: name)
                try? FileManager.default.createDirectory(at: coversFolder, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: target.path) { try? data.write(to: target, options: .atomic) }
                return target.path
            }
            if let index = games.firstIndex(where: { $0.id == incoming.id }) {
                Self.fold(incoming, cover: cover, into: &games[index])
            } else if let index = removed.firstIndex(where: { $0.id == incoming.id }) {
                Self.fold(incoming, cover: cover, into: &removed[index])
            } else {
                var game = incoming
                game.customCover = cover
                removed.append(game)
            }
            count += 1
        }
        var collectionCount = 0
        for collection in export.collections {
            collectionCount += 1
            if let index = collections.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(collection.name) == .orderedSame }) {
                for id in collection.gameIDs where !collections[index].gameIDs.contains(id) { collections[index].gameIDs.append(id) }
            } else {
                var copy = collection
                if collections.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
                collections.append(copy)
            }
        }
        return ImportSummary(games: count, collections: collectionCount)
    }

    static func fold(_ incoming: Game, cover: String?, into game: inout Game) {
        if incoming.playtime > game.playtime {
            game.playtime = incoming.playtime
            game.sessions = incoming.sessions
        }
        if let date = incoming.lastPlayed, date > (game.lastPlayed ?? .distantPast) { game.lastPlayed = date }
        if let last = incoming.lastLaunch, last.date > (game.lastLaunch?.date ?? .distantPast) { game.lastLaunch = last }
        game.launches = max(game.launches, incoming.launches)
        if game.options == GameOptions() { game.options = incoming.options }
        if game.customCover == nil, let cover { game.customCover = cover }
        if incoming.added.timeIntervalSince1970 > 0, incoming.added < game.added { game.added = incoming.added }
    }
}
