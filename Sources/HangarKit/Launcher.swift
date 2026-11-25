import Darwin
import Foundation
import SteamKit

/// How to start a game: a command, and how to find the game's own process afterwards
/// (the command itself exits at once, or stays as a launcher).
public struct LaunchPlan: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    /// Words found in the game's process path or arguments.
    public var processHints: [String]
    /// Variables added to the launch's environment (the game's options).
    public var environment: [String: String] = [:]
    /// For a Mac app opened by Launch Services: the arguments it gets.
    public var appArguments: [String] = []
    /// Where the command runs (a Wine program's own folder).
    public var workingDirectory: URL?
    /// Where the command's output goes, for a Wine build's messages (S-024). Nil discards it.
    public var outputFile: URL?
}

public enum LaunchError: Error, Sendable, Equatable {
    case crossOverMissing
    /// The game's runner (a Wine build, Game Porting Toolkit) isn't on this Mac anymore.
    case runnerMissing
    case filesMissing
    case noBottle
    /// A Heroic game, and Heroic isn't installed anymore (S-036).
    case heroicMissing
}

public enum LaunchPlanner {
    static let open = URL(fileURLWithPath: "/usr/bin/open")

    public static func plan(for game: Game, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        var plan = try basePlan(for: game, roots: roots)
        plan.environment.merge(game.options.environment) { $1 }
        if plan.executable == open, plan.arguments.count == 1, plan.arguments[0].hasSuffix(".app") {
            plan.appArguments = game.options.argumentList
        }
        return plan
    }

    static func basePlan(for game: Game, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        if let heroic = game.heroic {
            // Heroic starts it with the Wine settings it keeps for the game.
            guard let app = roots.heroicApp, FileManager.default.fileExists(atPath: app.path) else { throw .heroicMissing }
            guard let url = heroic.launchURL else { throw .filesMissing }
            return LaunchPlan(executable: open, arguments: [url.absoluteString], processHints: game.processHints)
        }
        if let path = game.options.runner, game.runner == .crossOver, game.steamID == nil {
            return try prefixPlan(for: game, runnerPath: path, roots: roots)
        }
        switch game.runner {
        case .native:
            // A Steam game on the Mac starts through Steam, so Steam's overlay and cloud saves work.
            if game.source == .steam, let id = game.steamID {
                // Steam can't pass an environment or arguments on; with them, Hangar opens the game's app itself.
                if !game.options.environment.isEmpty || !game.options.argumentList.isEmpty,
                   let app = macApp(in: URL(fileURLWithPath: game.path)) {
                    return LaunchPlan(executable: open, arguments: [app.path], processHints: game.processHints)
                }
                return LaunchPlan(executable: open, arguments: [SteamLink.run(appID: id).absoluteString], processHints: game.processHints)
            }
            guard FileManager.default.fileExists(atPath: game.path) else { throw .filesMissing }
            return LaunchPlan(executable: open, arguments: [game.path], processHints: game.processHints)
        case .crossOver:
            guard let wine = roots.wine, FileManager.default.isExecutableFile(atPath: wine.path) else { throw .crossOverMissing }
            guard let bottle = game.bottle else { throw .noBottle }
            if let id = game.steamID {
                // Through the bottle's Steam, which must be signed in.
                return LaunchPlan(executable: wine,
                                  arguments: ["--bottle", bottle, "--no-wait", "--cx-app", CrossOverScanner.steamWindowsFolder + "/steam.exe",
                                              "-silent", "-applaunch", id] + game.options.argumentList,
                                  processHints: game.processHints)
            }
            let args = game.options.argumentList
            if let exe = game.options.exe, !exe.isEmpty {
                return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--cx-app", exe] + args,
                                  processHints: game.processHints + [exeHint(exe)])
            }
            guard let exe = game.exe else { throw .filesMissing }
            if game.startsShortcut {
                return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--start", exe] + args, processHints: game.processHints)
            }
            return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--cx-app", exe] + args, processHints: game.processHints)
        case .wine, .gamePortingToolkit, .macRunner, .heroic:
            throw .runnerMissing
        }
    }

    /// A Windows program run by a Wine build or Game Porting Toolkit in a prefix of its own.
    static func prefixPlan(for game: Game, runnerPath: String, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        guard let runner = RunnerScanner.scan(roots).first(where: { $0.path == runnerPath && $0.runsPrefixes }),
              let wine = runner.wine else { throw .runnerMissing }
        let program: String
        if let exe = game.options.exe, !exe.isEmpty, let bottle = game.bottle,
           let mac = CrossOverScanner.macPath(exe, bottle: roots.bottles.appending(path: bottle)) {
            program = mac.path
        } else {
            program = game.path
        }
        guard FileManager.default.fileExists(atPath: program) else { throw .filesMissing }
        // A shortcut opens with Wine's start; an exe runs directly.
        let command = program.lowercased().hasSuffix(".lnk") ? ["start", "/unix", program] : [program]
        var plan = LaunchPlan(executable: URL(fileURLWithPath: wine), arguments: command + game.options.argumentList,
                              processHints: game.processHints + [exeHint(program)])
        plan.environment = ["WINEPREFIX": prefix(for: game, roots: roots).path, "WINEDEBUG": "-all"]
        plan.workingDirectory = URL(fileURLWithPath: program).deletingLastPathComponent()
        return plan
    }

    /// The game's own prefix: Prefixes/<title>-<short id>.
    public static func prefix(for game: Game, roots: LibraryRoots) -> URL {
        let safe = game.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var hash: UInt32 = 2166136261
        for byte in game.id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return roots.prefixes.appending(path: "\(safe)-\(String(hash, radix: 16))")
    }

    /// The words that find a Windows program's process: its file name.
    static func exeHint(_ exe: String) -> String {
        exe.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? exe
    }

    /// The game's .app in a Steam game's folder (Hollow Knight/hollow_knight.app), the folder itself when
    /// it is the app (Stardew Valley), or one a few folders down.
    public static func macApp(in folder: URL) -> URL? {
        SteamApp.macApp(in: folder)
    }

    /// Opens the bottle's Steam, to sign in.
    public static func openSteam(bottle: String, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        guard let wine = roots.wine, FileManager.default.isExecutableFile(atPath: wine.path) else { throw .crossOverMissing }
        return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--cx-app", CrossOverScanner.steamWindowsFolder + "/steam.exe"],
                          processHints: [])
    }

    /// A Windows game's id for a file added by hand, from its bottle and Windows path.
    public static func windowsPath(for file: URL, bottle: URL) -> String {
        let driveC = bottle.appending(path: "drive_c").standardizedFileURL.path
        let path = file.standardizedFileURL.path
        if path.hasPrefix(driveC + "/") { return "C:" + path.dropFirst(driveC.count) }
        return path
    }
}

/// A process on this Mac: its executable and arguments.
public struct RunningProcess: Sendable, Equatable {
    public var pid: pid_t
    public var path: String
    public var arguments: [String]

    public init(pid: pid_t, path: String, arguments: [String]) {
        self.pid = pid
        self.path = path
        self.arguments = arguments
    }

    /// True when a hint names this process: its folder for a Mac game, its exe for a Windows game.
    public func matches(_ hints: [String]) -> Bool {
        guard !hints.isEmpty else { return false }
        let haystack = ([path] + arguments).joined(separator: "\n").lowercased()
        return hints.contains { !$0.isEmpty && haystack.contains($0.lowercased()) }
    }
}

public enum ProcessList {
    /// The game's processes among those running, never this app or the launch command itself.
    public static func find(_ hints: [String], in processes: [RunningProcess]) -> [RunningProcess] {
        let me = getpid()
        // The launch command (open, or CrossOver's wine script run by perl) names the game too.
        return processes.filter { $0.pid != me && !$0.path.hasSuffix("/usr/bin/open") && !$0.arguments.contains("--bottle") && $0.matches(hints) }
    }

    /// This user's processes. Reads each one's arguments with sysctl (KERN_PROCARGS2).
    @concurrent
    public static func snapshot() async -> [RunningProcess] {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).compactMap { pid in
            guard pid > 0, let args = arguments(of: pid) else { return nil }
            return RunningProcess(pid: pid, path: args.path, arguments: args.arguments)
        }
    }

    static func arguments(of pid: pid_t) -> (path: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        func next() -> String? {
            guard index < size else { return nil }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let value = String(decoding: buffer[start..<index], as: UTF8.self)
            while index < size, buffer[index] == 0 { index += 1 }
            return value
        }
        guard let path = next() else { return nil }
        var arguments: [String] = []
        for _ in 0..<argc { if let arg = next() { arguments.append(arg) } }
        return (path, arguments)
    }
}
