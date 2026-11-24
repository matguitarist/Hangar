import Foundation

/// Valve's KeyValues text format (libraryfolders.vdf, appmanifest_<id>.acf, loginusers.vdf):
/// quoted keys followed by a quoted value or a { block }.
public indirect enum KeyValues: Sendable, Equatable {
    case text(String)
    case block([(String, KeyValues)])

    public static func == (a: KeyValues, b: KeyValues) -> Bool {
        switch (a, b) {
        case let (.text(x), .text(y)): x == y
        case let (.block(x), .block(y)): x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }

    /// The value of a key, ignoring case as Steam does.
    public subscript(_ key: String) -> KeyValues? {
        guard case let .block(pairs) = self else { return nil }
        return pairs.first { $0.0.caseInsensitiveCompare(key) == .orderedSame }?.1
    }

    public var string: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    /// The pairs of a block, in file order.
    public var pairs: [(String, KeyValues)] {
        if case let .block(pairs) = self { return pairs }
        return []
    }

    public static func parse(_ text: String) -> KeyValues {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        return .block(parser.pairs())
    }

    public static func read(_ url: URL) -> KeyValues? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0

        mutating func pairs() -> [(String, KeyValues)] {
            var result: [(String, KeyValues)] = []
            while let key = token() {
                if key == "}" { break }
                skipSpace()
                if index < scalars.count, scalars[index] == "{" {
                    index += 1
                    result.append((key, .block(pairs())))
                } else if let value = token(), value != "}" {
                    result.append((key, .text(value)))
                } else {
                    break
                }
            }
            return result
        }

        mutating func skipSpace() {
            while index < scalars.count {
                let c = scalars[index]
                if c == " " || c == "\t" || c == "\n" || c == "\r" {
                    index += 1
                } else if c == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                } else {
                    return
                }
            }
        }

        /// A quoted string, a bare word, or "}" (returned as the string "}").
        mutating func token() -> String? {
            skipSpace()
            guard index < scalars.count else { return nil }
            if scalars[index] == "}" { index += 1; return "}" }
            var out = String.UnicodeScalarView()
            if scalars[index] == "\"" {
                index += 1
                while index < scalars.count, scalars[index] != "\"" {
                    if scalars[index] == "\\", index + 1 < scalars.count {
                        index += 1
                        switch scalars[index] {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(scalars[index])
                        }
                    } else {
                        out.append(scalars[index])
                    }
                    index += 1
                }
                index += 1
            } else {
                while index < scalars.count, !" \t\n\r{}\"".unicodeScalars.contains(scalars[index]) {
                    out.append(scalars[index]); index += 1
                }
                if out.isEmpty { index += 1; return token() }
            }
            return String(out)
        }
    }
}
