import Darwin
import Foundation

/// How to start a game: a command, and how to find the game's own process afterwards
/// (the command itself exits at once, or stays as a launcher).
public struct LaunchPlan: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    /// Words found in the game's process path or arguments.
    public var processHints: [String]
    /// Variables added to the launch's environment (the game's options).
    public var environment: [String: String] = [:]
}

public enum LaunchError: Error, Sendable, Equatable {
    case crossOverMissing
    /// The game's runner (a Wine build, Game Porting Toolkit) isn't on this Mac anymore.
    case runnerMissing
    case filesMissing
    case noBottle
}

public enum LaunchPlanner {
    static let open = URL(fileURLWithPath: "/usr/bin/open")

    public static func plan(for game: Game, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        var plan = try basePlan(for: game, roots: roots)
        plan.environment = game.options.environment
        return plan
    }

    static func basePlan(for game: Game, roots: LibraryRoots) throws(LaunchError) -> LaunchPlan {
        switch game.runner {
        case .native:
            // A Steam game on the Mac starts through Steam, so Steam's overlay and cloud saves work.
            if game.source == .steam, let id = game.steamID {
                // Steam can't pass an environment on; with one, Hangar opens the game's app itself.
                if !game.options.environment.isEmpty, let app = macApp(in: URL(fileURLWithPath: game.path)) {
                    return LaunchPlan(executable: open, arguments: [app.path], processHints: game.processHints)
                }
                return LaunchPlan(executable: open, arguments: ["steam://rungameid/\(id)"], processHints: game.processHints)
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
                                              "-silent", "-applaunch", id],
                                  processHints: game.processHints)
            }
            guard let exe = game.exe else { throw .filesMissing }
            if game.startsShortcut {
                return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--start", exe], processHints: game.processHints)
            }
            return LaunchPlan(executable: wine, arguments: ["--bottle", bottle, "--no-wait", "--cx-app", exe], processHints: game.processHints)
        case .wine, .gamePortingToolkit, .macRunner:
            throw .runnerMissing
        }
    }

    /// The game's .app in a Steam game's folder (Hollow Knight/hollow_knight.app).
    public static func macApp(in folder: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().first { $0.hasSuffix(".app") }.map { folder.appending(path: $0) }
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
