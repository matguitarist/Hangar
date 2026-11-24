import Foundation

/// A copy of a game's saves, taken before it starts (S-022) or before a restore (S-023).
public struct SaveBackup: Codable, Sendable, Identifiable, Hashable {
    public enum Reason: String, Codable, Sendable { case launch, beforeRestore, byHand }

    /// One save file or folder, where it was and its name in the backup.
    public struct Item: Codable, Sendable, Hashable {
        public var source: String
        public var stored: String
    }

    /// The backup's folder name, which sorts by date.
    public var id: String
    public var date: Date
    public var reason: Reason
    public var items: [Item]
    public var bytes: Int64
    public var files: Int
    /// What the saves looked like (names, sizes, dates): the same fingerprint means nothing changed.
    public var fingerprint: String
}

/// Save backups in a folder, one subfolder per game, the last ten kept.
///   <root>/<game>/<yyyy-MM-dd'T'HH-mm-ss.SSS>/backup.json and items/<n>/<name>
public struct SaveBackupStore: Sendable {
    public let root: URL
    public static let keep = 10

    public init(root: URL) { self.root = root }

    func folder(_ gameID: String) -> URL {
        root.appending(path: gameID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? String($0) : "_" }.joined())
    }

    /// A game's backups, newest first.
    public func list(_ gameID: String) -> [SaveBackup] {
        let dir = folder(gameID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.compactMap { name in
            (try? Data(contentsOf: dir.appending(path: "\(name)/backup.json"))).flatMap { try? decoder.decode(SaveBackup.self, from: $0) }
        }
        .sorted { $0.date > $1.date }
    }

    /// The folder holding one backup's files.
    public func location(of backup: SaveBackup, gameID: String) -> URL {
        folder(gameID).appending(path: backup.id)
    }

    /// Copies the saves. Nil when there is nothing to copy, or nothing changed since the last backup.
    @discardableResult
    public func backUp(_ gameID: String, saves: [URL], reason: SaveBackup.Reason, now: Date = Date()) throws -> SaveBackup? {
        let fm = FileManager.default
        let saves = saves.filter { fm.fileExists(atPath: $0.path) }
        guard !saves.isEmpty else { return nil }
        let (fingerprint, bytes, files) = Self.fingerprint(saves)
        if list(gameID).first?.fingerprint == fingerprint { return nil }
        let stamp = Self.stamp.string(from: now)
        let target = folder(gameID).appending(path: stamp)
        let staging = folder(gameID).appending(path: ".\(stamp)-partial")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging.appending(path: "items"), withIntermediateDirectories: true)
        var items: [SaveBackup.Item] = []
        do {
            for (index, save) in saves.enumerated() {
                let stored = "items/\(index)/\(save.lastPathComponent)"
                try fm.createDirectory(at: staging.appending(path: "items/\(index)"), withIntermediateDirectories: true)
                try fm.copyItem(at: save, to: staging.appending(path: stored))
                items.append(SaveBackup.Item(source: save.path, stored: stored))
            }
            let backup = SaveBackup(id: stamp, date: now, reason: reason, items: items, bytes: bytes, files: files, fingerprint: fingerprint)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(backup).write(to: staging.appending(path: "backup.json"), options: .atomic)
            // Only a whole copy becomes a backup.
            try fm.moveItem(at: staging, to: target)
            prune(gameID)
            return backup
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Puts a backup's files back where they came from, replacing what is there.
    public func restore(_ backup: SaveBackup, gameID: String) throws {
        let fm = FileManager.default
        let dir = location(of: backup, gameID: gameID)
        for item in backup.items {
            let source = dir.appending(path: item.stored)
            let target = URL(fileURLWithPath: item.source)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Copy beside it first, so a failed copy leaves the current save in place.
            let incoming = target.deletingLastPathComponent().appending(path: ".hangar-restore-\(UUID().uuidString)")
            try fm.copyItem(at: source, to: incoming)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: incoming)
            } else {
                try fm.moveItem(at: incoming, to: target)
            }
        }
    }

    /// Keeps the last ten backups of a game.
    func prune(_ gameID: String) {
        for old in list(gameID).dropFirst(Self.keep) {
            try? FileManager.default.removeItem(at: location(of: old, gameID: gameID))
        }
    }

    /// Moves every backup to another folder (iCloud Drive and back). Backups already there stay.
    public func move(to other: SaveBackupStore) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        try fm.createDirectory(at: other.root, withIntermediateDirectories: true)
        for game in try fm.contentsOfDirectory(atPath: root.path) where !game.hasPrefix(".") {
            let from = root.appending(path: game), to = other.root.appending(path: game)
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            for backup in try fm.contentsOfDirectory(atPath: from.path) where !backup.hasPrefix(".") {
                if !fm.fileExists(atPath: to.appending(path: backup).path) {
                    try fm.moveItem(at: from.appending(path: backup), to: to.appending(path: backup))
                }
            }
            try? fm.removeItem(at: from)
        }
    }

    /// Names, sizes and dates of every file in the saves, hashed; with the total size and file count.
    static func fingerprint(_ saves: [URL]) -> (String, Int64, Int) {
        let fm = FileManager.default
        var lines: [String] = []
        var bytes: Int64 = 0
        func add(_ url: URL, _ name: String) {
            // A URL keeps the values it read once; a save written since must be read again.
            var url = url
            url.removeAllCachedResourceValues()
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            if values?.isDirectory == true { return }
            let size = Int64(values?.fileSize ?? 0)
            bytes += size
            lines.append("\(name)|\(size)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        for (index, save) in saves.enumerated() {
            add(save, "\(index)/\(save.lastPathComponent)")
            if let files = fm.enumerator(at: save, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) {
                for case let file as URL in files {
                    add(file, "\(index)/\(save.lastPathComponent)" + file.path.dropFirst(save.path.count))
                }
            }
        }
        lines.sort()
        var hash: UInt64 = 1469598103934665603
        for byte in lines.joined(separator: "\n").utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return (String(hash, radix: 16), bytes, lines.count)
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS"
        return f
    }()
}
