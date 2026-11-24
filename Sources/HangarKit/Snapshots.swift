import CryptoKit
import Foundation

/// A saved copy of a game's settings and bottle files, to roll back to.
public struct SettingsSnapshot: Codable, Sendable, Identifiable, Equatable {
    /// A bottle file as it was: its path in the bottle, and whether it was there.
    public struct File: Codable, Sendable, Equatable {
        public var path: String
        public var existed: Bool
    }

    public enum Reason: String, Codable, Sendable {
        case settings, launch, recipe, restore
    }

    public var id: UUID
    public var gameID: String
    public var date: Date
    public var reason: Reason
    /// The recipe applied after it, for reason .recipe.
    public var detail: String?
    /// When the person said the game worked with these settings.
    public var worked: Date?
    /// The runner's version then ("CrossOver 26.3").
    public var runner: String?
    public var bottle: String?
    public var files: [File]
    public var options: GameOptions
    /// A digest of the files and options, to skip a snapshot identical to the one before.
    public var digest: String
}

/// Snapshots in a folder: <folder>/<game>/<id>/snapshot.json and the files.
public struct SnapshotStore: Sendable {
    public let folder: URL
    /// Bottle files every snapshot keeps.
    public static let bottleFiles = ["cxbottle.conf", "system.reg", "user.reg", "userdef.reg"]
    /// Snapshots kept per game, besides those marked as working.
    public static let keep = 20

    public init(folder: URL) { self.folder = folder }

    func gameFolder(_ gameID: String) -> URL {
        let digest = SHA256.hash(data: Data(gameID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: digest)
    }

    /// Saves the game's options and its bottle's files (and any others a change will touch).
    /// When nothing changed since the last snapshot, returns that one instead of making a new one.
    @discardableResult
    public func take(_ game: Game, bottle: URL?, extraFiles: [String] = [], reason: SettingsSnapshot.Reason, detail: String? = nil,
                     runner: String? = nil, now: Date = Date()) throws -> SettingsSnapshot {
        let fm = FileManager.default
        let paths = bottle == nil ? [] : Array(Set(Self.bottleFiles + extraFiles)).sorted()
        var hasher = SHA256()
        var files: [SettingsSnapshot.File] = []
        var contents: [String: Data] = [:]
        for path in paths {
            let url = bottle!.appending(path: path)
            if let data = fm.contents(atPath: url.path) {
                files.append(.init(path: path, existed: true))
                contents[path] = data
                hasher.update(data: Data(path.utf8)); hasher.update(data: data)
            } else {
                files.append(.init(path: path, existed: false))
                hasher.update(data: Data("missing:\(path)".utf8))
            }
        }
        hasher.update(data: (try? JSONEncoder.snapshot.encode(game.options)) ?? Data())
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if reason != .recipe, let last = list(game.id).first, last.digest == digest, last.bottle == game.bottle { return last }

        let snapshot = SettingsSnapshot(id: UUID(), gameID: game.id, date: now, reason: reason, detail: detail, runner: runner,
                                        bottle: game.bottle, files: files, options: game.options, digest: digest)
        let dir = gameFolder(game.id).appending(path: snapshot.id.uuidString)
        try fm.createDirectory(at: dir.appending(path: "files"), withIntermediateDirectories: true)
        for (path, data) in contents {
            let target = dir.appending(path: "files").appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        try save(snapshot)
        prune(game.id)
        return snapshot
    }

    func save(_ snapshot: SettingsSnapshot) throws {
        let dir = gameFolder(snapshot.gameID).appending(path: snapshot.id.uuidString)
        try JSONEncoder.snapshot.encode(snapshot).write(to: dir.appending(path: "snapshot.json"), options: .atomic)
    }

    /// A game's snapshots, newest first.
    public func list(_ gameID: String) -> [SettingsSnapshot] {
        let dir = gameFolder(gameID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name in
            (try? Data(contentsOf: dir.appending(path: "\(name)/snapshot.json"))).flatMap { try? JSONDecoder.snapshot.decode(SettingsSnapshot.self, from: $0) }
        }
        .filter { $0.gameID == gameID }
        .sorted { $0.date > $1.date }
    }

    /// Puts the bottle's files back byte for byte (and removes those that weren't there), and
    /// returns the options to put back on the game.
    public func restore(_ snapshot: SettingsSnapshot, bottle: URL?) throws -> GameOptions {
        let fm = FileManager.default
        if let bottle {
            let source = gameFolder(snapshot.gameID).appending(path: "\(snapshot.id.uuidString)/files")
            for file in snapshot.files {
                let target = bottle.appending(path: file.path)
                if file.existed {
                    let data = try Data(contentsOf: source.appending(path: file.path))
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: target, options: .atomic)
                } else if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            }
        }
        return snapshot.options
    }

    /// Labels a snapshot as working ("worked on 12 Nov"). Working snapshots are never pruned.
    public func markWorked(_ snapshot: SettingsSnapshot, on date: Date = Date()) throws {
        var s = snapshot
        s.worked = date
        try save(s)
    }

    /// Keeps the newest snapshots and every working one.
    func prune(_ gameID: String) {
        let all = list(gameID)
        guard all.count > Self.keep else { return }
        for old in all.dropFirst(Self.keep) where old.worked == nil {
            try? FileManager.default.removeItem(at: gameFolder(gameID).appending(path: old.id.uuidString))
        }
    }
}

extension JSONEncoder {
    static let snapshot: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        // Seconds with their fraction: two snapshots in the same second still sort in order.
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

extension JSONDecoder {
    static let snapshot: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
