import Foundation

/// Something on disk the Storage page lists (S-039): a game's folder, a bottle, a prefix, or Hangar's own copies.
public struct StorageItem: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case games, bottles, prefixes, snapshots, saveBackups
    }

    public var id: String { kind.rawValue + ":" + path }
    public var name: String
    public var kind: Kind
    public var path: String
    public var bytes: Int64
    /// A prefix no game in the library uses anymore.
    public var unused = false

    public init(name: String, kind: Kind, path: String, bytes: Int64, unused: Bool = false) {
        self.name = name
        self.kind = kind
        self.path = path
        self.bytes = bytes
        self.unused = unused
    }
}

public enum StorageScanner {
    public struct Input: Sendable {
        public var games: [Game]
        public var bottles: URL
        public var bottleNames: [String]
        public var prefixes: URL
        /// The prefixes the library's games run in.
        public var usedPrefixes: Set<String>
        public var snapshots: URL
        public var saveBackups: URL

        public init(games: [Game], bottles: URL, bottleNames: [String], prefixes: URL, usedPrefixes: Set<String>, snapshots: URL, saveBackups: URL) {
            self.games = games
            self.bottles = bottles
            self.bottleNames = bottleNames
            self.prefixes = prefixes
            self.usedPrefixes = usedPrefixes
            self.snapshots = snapshots
            self.saveBackups = saveBackups
        }
    }

    /// Everything, largest first. A game in a bottle counts with its bottle, once.
    @concurrent
    public static func measure(_ input: Input) async -> [StorageItem] {
        var items: [StorageItem] = []
        let bottlesPath = input.bottles.standardizedFileURL.path + "/"
        var seen = Set<String>()
        for game in input.games where !game.path.isEmpty {
            let path = URL(fileURLWithPath: game.path).standardizedFileURL.path
            guard !(path + "/").hasPrefix(bottlesPath), seen.insert(path).inserted,
                  FileManager.default.fileExists(atPath: path) else { continue }
            items.append(StorageItem(name: game.title, kind: .games, path: path, bytes: size(of: URL(fileURLWithPath: path))))
        }
        for name in input.bottleNames {
            let url = input.bottles.appending(path: name)
            items.append(StorageItem(name: name, kind: .bottles, path: url.path, bytes: size(of: url)))
        }
        let prefixes = (try? FileManager.default.contentsOfDirectory(atPath: input.prefixes.path)) ?? []
        for name in prefixes.sorted() where !name.hasPrefix(".") {
            let url = input.prefixes.appending(path: name)
            items.append(StorageItem(name: name, kind: .prefixes, path: url.path, bytes: size(of: url),
                                     unused: !input.usedPrefixes.contains(url.standardizedFileURL.path)))
        }
        for (kind, url) in [(StorageItem.Kind.snapshots, input.snapshots), (.saveBackups, input.saveBackups)]
            where FileManager.default.fileExists(atPath: url.path) {
            items.append(StorageItem(name: url.lastPathComponent, kind: kind, path: url.path, bytes: size(of: url)))
        }
        return items.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
    }

    /// The bytes a folder or file takes on disk (allocated, so sparse and compressed files count as they are).
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let file = files?.nextObject() as? URL {
            guard let v = try? file.resourceValues(forKeys: keys), v.isDirectory != true, v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Totals by kind, for the bar at the top.
    public static func totals(_ items: [StorageItem]) -> [StorageItem.Kind: Int64] {
        items.reduce(into: [:]) { $0[$1.kind, default: 0] += $1.bytes }
    }
}

extension SnapshotStore {
    /// Delete Old Snapshots: keeps each game's newest `keep` and every one marked as working. Returns how many went.
    @discardableResult
    public func deleteOld(gameIDs: [String], keep: Int = 3) -> Int {
        var removed = 0
        for id in gameIDs {
            for old in list(id).dropFirst(keep) where old.worked == nil {
                if (try? FileManager.default.removeItem(at: gameFolder(id).appending(path: old.id.uuidString))) != nil { removed += 1 }
            }
        }
        return removed
    }
}

extension SaveBackupStore {
    /// Delete Old Backups: keeps each game's newest `keep`. Returns how many went.
    @discardableResult
    public func deleteOld(gameIDs: [String], keep: Int = 3) -> Int {
        var removed = 0
        for id in gameIDs {
            for old in list(id).dropFirst(keep) {
                if (try? FileManager.default.removeItem(at: location(of: old, gameID: id))) != nil { removed += 1 }
            }
        }
        return removed
    }
}
