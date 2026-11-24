import Foundation

/// Why a Windows game quit, read from its Wine log (S-024): known lines mapped to a plain reason and a fix.
public struct CrashReason: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A Windows runtime the game needs isn't in the bottle.
        case missingRuntime(Runtime)
        /// Another Windows file the game needs isn't there ("steam_api64.dll").
        case missingFile(String)
        /// The graphics path can't do what the game asks; another one can.
        case needsGraphics(GraphicsBackend)
        case outOfMemory
    }

    public enum Runtime: String, Sendable, CaseIterable {
        case visualCpp = "Microsoft Visual C++ 2015-2022 Redistributable"
        case directX = "DirectX for Modern Games"
        case dotNet = "Microsoft .NET Framework 4.8"
        case xna = "Microsoft XNA Framework Redistributable 4.0"
        case physX = "NVIDIA PhysX"
    }

    public var kind: Kind
    /// The log line that told.
    public var line: String

    /// The reason in plain words, for the first line of the notice.
    public var title: String {
        switch kind {
        case .missingRuntime(.visualCpp): String(localized: "Missing Visual C++ 2022 runtime", bundle: .main)
        case .missingRuntime(.directX): String(localized: "Missing DirectX runtime", bundle: .main)
        case .missingRuntime(.dotNet): String(localized: "Missing .NET Framework", bundle: .main)
        case .missingRuntime(.xna): String(localized: "Missing XNA Framework", bundle: .main)
        case .missingRuntime(.physX): String(localized: "Missing PhysX", bundle: .main)
        case let .missingFile(name): String(localized: "Missing \(name)", bundle: .main)
        case .needsGraphics(.dxvk): String(localized: "This game needs DXVK", bundle: .main)
        case .needsGraphics(.d3dMetal): String(localized: "This game needs D3DMetal", bundle: .main)
        case let .needsGraphics(other): String(localized: "This game needs \(other.title)", bundle: .main)
        case .outOfMemory: String(localized: "The Mac ran out of memory", bundle: .main)
        }
    }

    /// What to do about it.
    public var advice: String {
        switch kind {
        case let .missingRuntime(runtime):
            String(localized: "In CrossOver, choose Install Software for the bottle and search for “\(runtime.rawValue)”.", bundle: .main)
        case .missingFile:
            String(localized: "Reinstall the game, or check its files in Steam.", bundle: .main)
        case let .needsGraphics(backend):
            String(localized: "Switch the bottle's graphics to \(backend.title). Hangar takes a snapshot first.", bundle: .main)
        case .outOfMemory:
            String(localized: "Quit other apps, or lower the game's settings.", bundle: .main)
        }
    }
}

public enum CrashReadout {
    /// A game that quits sooner than this is read as a crash.
    public static let window: TimeInterval = 60

    /// The most telling reason in a Wine log, or nil when no known line is in it.
    /// Missing runtimes come first: a game without them can fail in every other way afterwards.
    public static func reason(in log: String) -> CrashReason? {
        var found: [(rank: Int, reason: CrashReason)] = []
        LogLinesScan.forEach(log) { line in
            if let r = match(line) { found.append(r) }
        }
        return found.min { $0.rank < $1.rank }?.reason
    }

    static let runtimeDLLs: [(prefix: String, runtime: CrashReason.Runtime)] = [
        ("msvcp1", .visualCpp), ("vcruntime1", .visualCpp), ("msvcr1", .visualCpp), ("concrt1", .visualCpp), ("vcomp1", .visualCpp),
        ("d3dx9_", .directX), ("d3dx10_", .directX), ("d3dx11_", .directX), ("d3dcompiler_4", .directX), ("xinput1_", .directX),
        ("x3daudio1_", .directX), ("xaudio2_", .directX), ("xapofx1_", .directX),
        ("mscoree", .dotNet), ("microsoft.xna", .xna), ("physxloader", .physX), ("physx3", .physX), ("physxcore", .physX),
    ]

    static func match(_ line: Substring) -> (Int, CrashReason)? {
        let lower = line.lowercased()
        let text = String(line).trimmingCharacters(in: .whitespaces)
        // err:module:import_dll Library MSVCP140.dll (which is needed by L"C:\…\Game.exe") not found
        if lower.contains("import_dll"), lower.contains("not found"), let name = dllName(in: String(line)) {
            let lowerName = name.lowercased()
            if let runtime = runtimeDLLs.first(where: { lowerName.hasPrefix($0.prefix) })?.runtime {
                return (0, CrashReason(kind: .missingRuntime(runtime), line: text))
            }
            return (2, CrashReason(kind: .missingFile(name), line: text))
        }
        if lower.contains("wine-mono") || lower.contains("wine mono") || (lower.contains("mscoree") && lower.contains("not")) {
            return (0, CrashReason(kind: .missingRuntime(.dotNet), line: text))
        }
        if lower.contains("d3d11createdevice") && (lower.contains("fail") || lower.contains("e_fail") || lower.contains("not supported"))
            || lower.contains("feature level") && lower.contains("not supported") {
            return (1, CrashReason(kind: .needsGraphics(.dxvk), line: text))
        }
        if lower.contains("d3d12createdevice") && (lower.contains("fail") || lower.contains("not supported")) {
            return (1, CrashReason(kind: .needsGraphics(.d3dMetal), line: text))
        }
        if lower.contains("out of memory") || lower.contains("e_outofmemory") || lower.contains("std::bad_alloc")
            || lower.contains("err:virtual") && lower.contains("failed") {
            return (3, CrashReason(kind: .outOfMemory, line: text))
        }
        return nil
    }

    /// "MSVCP140.dll" from an import_dll line.
    static func dllName(in line: String) -> String? {
        guard let range = line.range(of: #"Library\s+([^\s(]+\.(dll|DLL|Dll))"#, options: .regularExpression) else { return nil }
        return line[range].split(whereSeparator: \.isWhitespace).last.map(String.init)
    }
}

/// Lines of a log, without a Regex per line.
enum LogLinesScan {
    static func forEach(_ text: String, _ body: (Substring) -> Void) {
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            body(line)
        }
    }
}

extension LaunchPlan {
    /// The same launch, with Wine's messages written to a file: CrossOver's own --cx-log, or the
    /// command's output for a Wine build or Game Porting Toolkit (with errors on, fixme lines off).
    public func loggingWine(to file: URL) -> LaunchPlan {
        var plan = self
        if arguments.first == "--bottle" {
            plan.arguments = ["--cx-log", file.path] + arguments
        } else if environment["WINEPREFIX"] != nil {
            plan.environment["WINEDEBUG"] = "fixme-all"
            plan.outputFile = file
        } else {
            return self
        }
        return plan
    }
}
