import Foundation

/// CrossOver's cxbottle.conf: [Sections] of "Key" = "Value" lines, with ;; comments.
/// Changes touch only the line they change, so the rest of the file stays byte for byte.
public struct ConfFile: Sendable, Equatable {
    public private(set) var text: String

    public init(text: String) { self.text = text }

    public static func read(_ url: URL) throws -> ConfFile {
        ConfFile(text: try String(contentsOf: url, encoding: .utf8))
    }

    public func write(to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    /// The range of lines in a section, after its header, or nil when there is none.
    private func section(_ name: String, in lines: [Substring]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { Self.header($0) == name }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { Self.header($0) != nil } ?? lines.count
        return (header + 1)..<end
    }

    static func header(_ line: Substring) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), t.hasSuffix("]") else { return nil }
        return String(t.dropFirst().dropLast())
    }

    /// "Key" = "Value" → (Key, Value).
    static func pair(_ line: Substring) -> (String, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\""), let eq = t.range(of: "=") else { return nil }
        let key = t[..<eq.lowerBound].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        var value = t[eq.upperBound...].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
        return (key, value)
    }

    public func value(_ key: String, in section: String) -> String? {
        let lines = self.lines
        guard let range = self.section(section, in: lines) else { return nil }
        for i in range { if let (k, v) = Self.pair(lines[i]), k == key { return v } }
        return nil
    }

    /// Sets a key, or removes it with nil. A new key goes after the section's last key;
    /// a new section goes at the end of the file.
    public mutating func set(_ key: String, _ value: String?, in section: String) {
        var lines = self.lines.map(String.init)
        let line = value.map { "\"\(key)\" = \"\($0)\"" }
        if let range = self.section(section, in: self.lines) {
            if let i = range.first(where: { Self.pair(Substring(lines[$0]))?.0 == key }) {
                if let line { lines[i] = line } else { lines.remove(at: i) }
            } else if let line {
                let last = range.last(where: { Self.pair(Substring(lines[$0])) != nil }) ?? (range.lowerBound - 1)
                lines.insert(line, at: last + 1)
            }
        } else if let line {
            if lines.last == "" { lines.removeLast() }
            lines += ["[\(section)]", line, ""]
        }
        text = lines.joined(separator: "\n")
    }
}

/// A Wine registry file (user.reg, system.reg): [Key\\Path] timestamp sections of "Name"=value lines.
/// Like ConfFile, a change touches only its own lines.
public struct RegFile: Sendable, Equatable {
    public private(set) var text: String

    public init(text: String) { self.text = text }

    public static func read(_ url: URL) throws -> RegFile {
        RegFile(text: try String(contentsOf: url, encoding: .utf8))
    }

    public func write(to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// A key as Windows writes it (Software\Wine\Mac Driver), as the file writes it (Software\\Wine\\Mac Driver).
    static func escaped(_ key: String) -> String { key.replacingOccurrences(of: "\\", with: "\\\\") }

    private static func header(_ line: Substring) -> String? {
        guard line.hasPrefix("["), let close = line.lastIndex(of: "]") else { return nil }
        return String(line[line.index(after: line.startIndex)..<close])
    }

    private func section(_ key: String, in lines: [Substring]) -> Range<Int>? {
        let wanted = Self.escaped(key).lowercased()
        guard let header = lines.firstIndex(where: { Self.header($0)?.lowercased() == wanted }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { Self.header($0) != nil } ?? lines.count
        return (header + 1)..<end
    }

    private static func name(_ line: Substring) -> String? {
        guard line.hasPrefix("\""), let end = line.dropFirst().firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: line.startIndex)..<end])
    }

    /// The raw value after "Name"=, such as "y" (quotes included) or dword:00000001.
    public func value(_ name: String, in key: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let range = section(key, in: lines) else { return nil }
        for i in range where Self.name(lines[i])?.caseInsensitiveCompare(name) == .orderedSame {
            return lines[i].split(separator: "=", maxSplits: 1).last.map(String.init)
        }
        return nil
    }

    /// A string value without its quotes.
    public func string(_ name: String, in key: String) -> String? {
        guard let raw = value(name, in: key), raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return nil }
        return String(raw.dropFirst().dropLast())
    }

    /// Sets a raw value ("\"y\"", dword:00000001), or removes it with nil. A new key goes at the end of the file.
    public mutating func set(_ name: String, raw value: String?, in key: String, now: Date = Date()) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let line = value.map { "\"\(name)\"=\($0)" }
        if let range = section(key, in: text.split(separator: "\n", omittingEmptySubsequences: false)) {
            if let i = range.first(where: { Self.name(Substring(lines[$0]))?.caseInsensitiveCompare(name) == .orderedSame }) {
                if let line { lines[i] = line } else { lines.remove(at: i) }
            } else if let line {
                // After the section's last value, before the blank line that ends it.
                var at = range.upperBound
                while at > range.lowerBound, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                lines.insert(line, at: at)
            }
        } else if let line {
            while lines.last == "" { lines.removeLast() }
            lines += ["", "[\(Self.escaped(key))] \(Int(now.timeIntervalSince1970))", line, ""]
        }
        text = lines.joined(separator: "\n")
    }

    public mutating func setString(_ name: String, _ value: String?, in key: String) {
        set(name, raw: value.map { "\"\($0)\"" }, in: key)
    }
}

/// The way a Windows game's graphics reach Metal (CX_GRAPHICS_BACKEND).
public enum GraphicsBackend: String, Sendable, CaseIterable, Codable {
    /// CrossOver picks: the key isn't set.
    case auto = ""
    case d3dMetal = "d3dmetal"
    case dxmt = "dxmt"
    case dxvk = "dxvk"
    case wined3d = "wined3d"

    public var title: String {
        switch self {
        case .auto: String(localized: "Auto", bundle: .main)
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wined3d: "Wine"
        }
    }
}

/// A bottle's settings, as CrossOver's Bottle Settings show them.
public struct BottleSettings: Sendable, Equatable, Codable {
    public var graphics: GraphicsBackend = .auto
    public var msync = false
    public var highResolution = false
    public var metalFX = false
    public var avx = false

    public init(graphics: GraphicsBackend = .auto, msync: Bool = false, highResolution: Bool = false, metalFX: Bool = false, avx: Bool = false) {
        self.graphics = graphics
        self.msync = msync
        self.highResolution = highResolution
        self.metalFX = metalFX
        self.avx = avx
    }

    static let env = "EnvironmentVariables"
    static let macDriver = "Software\\Wine\\Mac Driver"

    public static func conf(_ bottle: URL) -> URL { bottle.appending(path: "cxbottle.conf") }
    public static func userReg(_ bottle: URL) -> URL { bottle.appending(path: "user.reg") }

    /// Reads cxbottle.conf's [EnvironmentVariables] and RetinaMode in user.reg (Wine's high resolution switch).
    public static func read(bottle: URL) -> BottleSettings {
        let conf = (try? ConfFile.read(conf(bottle))) ?? ConfFile(text: "")
        let reg = try? RegFile.read(userReg(bottle))
        func on(_ key: String) -> Bool { conf.value(key, in: env) == "1" }
        return BottleSettings(graphics: GraphicsBackend(rawValue: conf.value("CX_GRAPHICS_BACKEND", in: env)?.lowercased() ?? "") ?? .auto,
                              msync: on("WINEMSYNC"),
                              highResolution: reg?.string("RetinaMode", in: macDriver)?.lowercased().hasPrefix("y") == true,
                              metalFX: on("D3DM_ENABLE_METALFX"),
                              avx: on("ROSETTA_ADVERTISE_AVX"))
    }

    /// Writes only what differs from the bottle's current settings. Returns the files it changed.
    @discardableResult
    public func write(bottle: URL) throws -> [URL] {
        let current = Self.read(bottle: bottle)
        var changed: [URL] = []
        let confURL = Self.conf(bottle)
        var conf = try ConfFile.read(confURL)
        let before = conf
        func flag(_ key: String, _ value: Bool, _ old: Bool) {
            if value != old { conf.set(key, value ? "1" : nil, in: Self.env) }
        }
        if graphics != current.graphics { conf.set("CX_GRAPHICS_BACKEND", graphics == .auto ? nil : graphics.rawValue, in: Self.env) }
        flag("WINEMSYNC", msync, current.msync)
        flag("D3DM_ENABLE_METALFX", metalFX, current.metalFX)
        flag("ROSETTA_ADVERTISE_AVX", avx, current.avx)
        if conf != before {
            try conf.write(to: confURL)
            changed.append(confURL)
        }
        if highResolution != current.highResolution {
            let regURL = Self.userReg(bottle)
            var reg = (try? RegFile.read(regURL)) ?? RegFile(text: "WINE REGISTRY Version 2\n")
            reg.setString("RetinaMode", highResolution ? "y" : "n", in: Self.macDriver)
            try reg.write(to: regURL)
            changed.append(regURL)
        }
        return changed
    }
}
