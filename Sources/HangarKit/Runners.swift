import Foundation

/// A runner installed on this Mac: CrossOver, a Wine build, Game Porting Toolkit, or MacRunner.
public struct InstalledRunner: Sendable, Hashable, Identifiable {
    public var kind: RunnerKind
    /// The name people know it by: "CrossOver", "Wine Stable", "Game Porting Toolkit".
    public var name: String
    public var version: String?
    /// The app or folder it lives in.
    public var path: String
    /// The wine command that runs a Windows program, when it has one.
    public var wine: String?

    public var id: String { path }

    public init(kind: RunnerKind, name: String, version: String?, path: String, wine: String?) {
        self.kind = kind
        self.name = name
        self.version = version
        self.path = path
        self.wine = wine
    }

    /// True when Hangar can run a Windows program in a prefix of its own with it.
    public var runsPrefixes: Bool { (kind == .wine || kind == .gamePortingToolkit) && wine != nil }
}

public enum RunnerScanner {
    /// Wine builds packaged as apps (Gcenx's builds, installed with Homebrew casks).
    static let wineApps = ["Wine Stable", "Wine Devel", "Wine Staging", "Wine Crossover"]

    /// Every runner on this Mac, CrossOver first.
    public static func scan(_ roots: LibraryRoots) -> [InstalledRunner] {
        let fm = FileManager.default
        var runners: [InstalledRunner] = []
        if let app = roots.crossOverApp, fm.fileExists(atPath: app.path) {
            runners.append(InstalledRunner(kind: .crossOver, name: "CrossOver", version: version(of: app), path: app.path,
                                           wine: roots.wine?.path))
        }
        for folder in roots.appFolders {
            for name in wineApps {
                let app = folder.appending(path: "\(name).app")
                guard fm.fileExists(atPath: app.path), !runners.contains(where: { $0.path == app.path }) else { continue }
                runners.append(InstalledRunner(kind: .wine, name: name, version: version(of: app), path: app.path,
                                               wine: wineCommand(in: app.appending(path: "Contents/Resources/wine/bin"))))
            }
            let gptk = folder.appending(path: "Game Porting Toolkit.app")
            if fm.fileExists(atPath: gptk.path) {
                runners.append(InstalledRunner(kind: .gamePortingToolkit, name: "Game Porting Toolkit", version: version(of: gptk),
                                               path: gptk.path, wine: wineCommand(in: gptk.appending(path: "Contents/Resources/wine/bin"))))
            }
            let macRunner = folder.appending(path: "MacRunner.app")
            if fm.fileExists(atPath: macRunner.path) {
                runners.append(InstalledRunner(kind: .macRunner, name: "MacRunner", version: version(of: macRunner),
                                               path: macRunner.path, wine: nil))
            }
        }
        // Apple's Game Porting Toolkit from its Homebrew tap: a folder, not an app.
        for folder in roots.toolFolders {
            let brew = folder.appending(path: "game-porting-toolkit")
            if fm.fileExists(atPath: brew.path), let wine = wineCommand(in: brew.appending(path: "bin")) {
                runners.append(InstalledRunner(kind: .gamePortingToolkit, name: "Game Porting Toolkit",
                                               version: brewVersion(brew), path: brew.resolvingSymlinksInPath().path, wine: wine))
            }
        }
        return runners
    }

    /// wine, or wine64 in older builds.
    static func wineCommand(in bin: URL) -> String? {
        ["wine", "wine64"].map { bin.appending(path: $0).path }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func version(of app: URL) -> String? {
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any]
        return (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
    }

    /// A Homebrew keg's version is its folder name: /usr/local/Cellar/game-porting-toolkit/1.1.
    static func brewVersion(_ link: URL) -> String? {
        let real = link.resolvingSymlinksInPath()
        return real == link ? nil : real.lastPathComponent
    }
}
