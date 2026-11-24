import Foundation
import LogKit

/// Wine's log lines for LogKit's viewer: "1712.032:0024:0028:err:module:import_dll Library … not found".
/// The time (with +timestamp), process and thread ids, the class (err, warn, fixme, trace), the channel and function.
public enum WineLog {
    public static let parser = LineLogParser(parseLine: parseLine)

    public static func parseLine(_ line: Substring) -> ParsedLine? {
        let parts = line.split(separator: ":", maxSplits: 6, omittingEmptySubsequences: false)
        // Find the class word among the first parts: everything before it is time and ids.
        guard let classIndex = parts.prefix(4).firstIndex(where: { ["err", "warn", "fixme", "trace", "info"].contains($0) }),
              parts.count > classIndex + 2 else { return nil }
        let ids = parts[..<classIndex]
        guard ids.allSatisfy({ $0.allSatisfy { $0.isHexDigit || $0 == "." } }) else { return nil }
        let time = ids.first.flatMap { $0.contains(".") ? String($0) : nil }
        let level: LogLevel = switch parts[classIndex] {
        case "err": .error
        case "warn": .warning
        case "fixme": .debug
        case "trace": .trace
        default: .info
        }
        let rest = parts[(classIndex + 2)...].joined(separator: ":")
        let space = rest.firstIndex(of: " ") ?? rest.endIndex
        let function = String(rest[..<space])
        let message = rest[space...].trimmingCharacters(in: .whitespaces)
        return ParsedLine(time: time, level: level, code: function.isEmpty ? nil : function,
                          source: String(parts[classIndex + 1]), message: message.isEmpty ? function : message)
    }
}
