import Foundation

/// Steam's binary KeyValues, as in appcache/stats/*.bin: a type byte, a name, a value; 8 ends a table.
public enum BinaryKeyValues {
    public indirect enum Value: Sendable, Equatable {
        case table([String: Value])
        case string(String)
        case int(Int32)
        case float(Float)
        case uint64(UInt64)

        public subscript(key: String) -> Value? {
            if case let .table(entries) = self { return entries[key] }
            return nil
        }

        public var table: [String: Value] {
            if case let .table(entries) = self { return entries }
            return [:]
        }

        public var string: String? {
            switch self {
            case let .string(s): s
            case let .int(i): String(i)
            default: nil
            }
        }

        public var int: Int64? {
            switch self {
            case let .int(i): Int64(i)
            case let .uint64(u): Int64(truncatingIfNeeded: u)
            case let .string(s): Int64(s)
            default: nil
            }
        }
    }

    /// The root table, or nil when the bytes aren't binary KeyValues.
    public static func parse(_ data: Data) -> Value? {
        let bytes = [UInt8](data)
        var index = 0
        guard let table = readTable(bytes, &index) else { return nil }
        return .table(table)
    }

    private static func readTable(_ b: [UInt8], _ i: inout Int) -> [String: Value]? {
        var table: [String: Value] = [:]
        while i < b.count {
            let type = b[i]
            i += 1
            if type == 8 { return table }
            guard let key = readString(b, &i) else { return nil }
            switch type {
            case 0:
                guard let inner = readTable(b, &i) else { return nil }
                table[key] = .table(inner)
            case 1:
                guard let s = readString(b, &i) else { return nil }
                table[key] = .string(s)
            case 2:
                guard i + 4 <= b.count else { return nil }
                table[key] = .int(Int32(bitPattern: UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24))
                i += 4
            case 3:
                guard i + 4 <= b.count else { return nil }
                let bits = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
                table[key] = .float(Float(bitPattern: bits))
                i += 4
            case 7:
                guard i + 8 <= b.count else { return nil }
                var value: UInt64 = 0
                for n in 0..<8 { value |= UInt64(b[i + n]) << (8 * UInt64(n)) }
                table[key] = .uint64(value)
                i += 8
            default:
                return nil
            }
        }
        return table
    }

    private static func readString(_ b: [UInt8], _ i: inout Int) -> String? {
        guard let end = b[i...].firstIndex(of: 0) else { return nil }
        let s = String(decoding: b[i..<end], as: UTF8.self)
        i = end + 1
        return s
    }
}

/// How many of a Steam game's achievements are unlocked, from Steam's own files on this Mac (S-041).
public struct AchievementSummary: Sendable, Equatable {
    public struct Unlock: Sendable, Equatable {
        public var name: String
        public var date: Date
    }

    public var total: Int
    public var unlocked: Int
    /// The last ones unlocked, newest first (at most three).
    public var recent: [Unlock]

    public var fraction: Double { total > 0 ? Double(unlocked) / Double(total) : 0 }
}

public enum SteamAchievements {
    /// Reads appcache/stats/UserGameStatsSchema_<app>.bin (names and bits) and the newest
    /// UserGameStats_<user>_<app>.bin (unlocked bits and times). Nil without a schema or achievements.
    public static func read(steamRoot: URL, appID: String, language: String = "english") -> AchievementSummary? {
        let stats = steamRoot.appending(path: "appcache/stats")
        guard let schemaData = try? Data(contentsOf: stats.appending(path: "UserGameStatsSchema_\(appID).bin")),
              let schema = BinaryKeyValues.parse(schemaData) else { return nil }
        let user = userFile(in: stats, appID: appID).flatMap { try? Data(contentsOf: $0) }.flatMap(BinaryKeyValues.parse)
        return summary(schema: schema, user: user, language: language)
    }

    public static func summary(schema: BinaryKeyValues.Value, user: BinaryKeyValues.Value?, language: String = "english") -> AchievementSummary? {
        // The schema's root is the app id; its stats hold the achievement blocks.
        guard let app = schema.table.values.first, let stats = app["stats"]?.table else { return nil }
        let cache = user?["cache"]
        var total = 0
        var unlocked = 0
        var unlocks: [AchievementSummary.Unlock] = []
        for (statID, stat) in stats {
            let type = stat["type"]?.string?.uppercased()
            guard type == "ACHIEVEMENTS" || type == "4" else { continue }
            let bits = stat["bits"]?.table ?? [:]
            total += bits.count
            let data = UInt32(truncatingIfNeeded: cache?[statID]?["data"]?.int ?? 0)
            let times = cache?[statID]?["AchievementTimes"]?.table ?? [:]
            for (bitKey, bit) in bits {
                guard let index = Int(bitKey), index < 32, data & (1 << UInt32(index)) != 0 else { continue }
                unlocked += 1
                if let time = times[bitKey]?.int, time > 0 {
                    let display = bit["display"]?["name"]
                    let name = display?[language]?.string ?? display?["english"]?.string ?? bit["name"]?.string ?? bitKey
                    unlocks.append(.init(name: name, date: Date(timeIntervalSince1970: TimeInterval(time))))
                }
            }
        }
        guard total > 0 else { return nil }
        let recent = unlocks.sorted { $0.date > $1.date }.prefix(3)
        return AchievementSummary(total: total, unlocked: unlocked, recent: Array(recent))
    }

    /// The newest stats file for the app, whatever account it belongs to.
    static func userFile(in stats: URL, appID: String) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stats.path)) ?? []
        return names.filter { $0.hasPrefix("UserGameStats_") && $0.hasSuffix("_\(appID).bin") }
            .map { stats.appending(path: $0) }
            .max { modified($0) < modified($1) }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Steam's language name for the app's language ("french" for fr).
    public static func language(for code: String?) -> String {
        switch code?.prefix(2) {
        case "fr": "french"
        case "de": "german"
        case "es": "spanish"
        case "it": "italian"
        case "ja": "japanese"
        default: "english"
        }
    }
}
