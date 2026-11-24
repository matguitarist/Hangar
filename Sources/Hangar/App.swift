import AppKit
import LogKit
import SwiftUI
import HangarKit

// Hangar
//   Hangar                          the app, with the library in ~/Library/Application Support/Hangar
//   APP_STORE=<file> Hangar         a test run: the library in <file>, its log next to it; never reads or launches real games
//   APP_SNAPSHOT=<dir> Hangar       save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Hangar               with APP_STORE: sample data for snapshots (tools/snap.sh)
//   APP_FIXTURES=<dir> Hangar       with APP_STORE: scan the sample library in Tests/Fixtures (copied to /tmp)
//   Hangar --selftest               run the self-test in a test run and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Hangar          run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Hangar               draw the 8 pt grid and the layout probes over the window

@main
struct HangarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Hangar", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            HangarCommands(model: model, menu: MenuState.shared)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }

        WindowGroup("Wine Log", id: "wine-log", for: String.self) { $gameID in
            WineLogWindow(gameID: gameID)
                .environment(model)
                .themed()
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        Store.log.flushFile()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where Hangar keeps its data: ~/Library/Application Support/Hangar/library.json and the log.
/// With APP_STORE set (only to a file in /tmp), the app is a test run and never touches real games.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Hangar", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            // A test store must live in /tmp, so a test can never write over the real library.
            precondition(path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/"), "APP_STORE must be a file in /tmp")
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "library.json")
    }

    /// The log: LogKit's default file, or <store>.log next to a test store.
    static var logURL: URL {
        isOverridden ? url.deletingPathExtension().appendingPathExtension("log") : LogStore.defaultFileURL(app: "Hangar")
    }

    static let log = LogStore(fileURL: logURL)

    /// Cached Steam art and chosen covers: Covers/ next to the library, or <store>-covers in a test run.
    static var coversFolder: URL {
        isOverridden ? URL(fileURLWithPath: url.deletingPathExtension().path + "-covers") : folder.appending(path: "Covers")
    }

    /// A file a test run makes next to the store. They all live in <store>-run/, which the
    /// self-test and snapshot scripts remove at the start, so no run sees another's leftovers.
    static func runFile(_ name: String) -> URL {
        URL(fileURLWithPath: url.deletingPathExtension().path + "-run").appending(path: name)
    }

    /// Settings snapshots: Snapshots/ next to the library, or <store>-run/snapshots in a test run.
    static var snapshotsFolder: URL {
        isOverridden ? runFile("snapshots") : folder.appending(path: "Snapshots")
    }

    /// The recipe manifest: the bundled one, or in a test run the sample (APP_FIXTURES/recipes.json).
    static var recipesURL: URL? {
        guard isOverridden else { return Bundle.main.url(forResource: "recipes", withExtension: "json") }
        return ProcessInfo.processInfo.environment["APP_FIXTURES"].map { URL(fileURLWithPath: $0).appending(path: "recipes.json") }
    }

    /// The runner versions seen last: runners.json next to the library, or <store>-run/runners.json in a test run.
    static var runnerVersionsURL: URL {
        isOverridden ? runFile("runners.json") : folder.appending(path: "runners.json")
    }

    /// AppleGamingWiki's verdicts, cached: Compatibility/ next to the library, or <store>-run/agw in a test run.
    static var compatibilityFolder: URL {
        isOverridden ? runFile("agw") : folder.appending(path: "Compatibility")
    }

    /// A test run never asks the wiki: it reads the sample pages (APP_FIXTURES/AppleGamingWiki), or nothing.
    static var compatibilityFetch: CompatibilityCache.Fetch {
        guard isOverridden else { return CompatibilityCache.network }
        let fixtures = ProcessInfo.processInfo.environment["APP_FIXTURES"] ?? "/nonexistent"
        return CompatibilityCache.folder(URL(fileURLWithPath: fixtures).appending(path: "AppleGamingWiki"))
    }

    /// PCGamingWiki's save paths, cached: PCGamingWiki/ next to the library, or <store>-run/pcgw in a test run.
    static var gameDataFolder: URL {
        isOverridden ? runFile("pcgw") : folder.appending(path: "PCGamingWiki")
    }

    /// A test run never asks the wiki: it reads the sample pages (APP_FIXTURES/PCGamingWiki), or nothing.
    static var gameDataFetch: GameDataCache.Fetch {
        guard isOverridden else { return GameDataCache.network }
        let fixtures = ProcessInfo.processInfo.environment["APP_FIXTURES"] ?? "/nonexistent"
        return GameDataCache.folder(URL(fileURLWithPath: fixtures).appending(path: "PCGamingWiki"))
    }

    /// Save backups (S-022): Save Backups/ next to the library, or Hangar/Save Backups in iCloud Drive.
    /// A test run keeps both in <store>-run.
    static func saveBackupsFolder(iCloud: Bool) -> URL {
        if isOverridden { return runFile(iCloud ? "icloud-save-backups" : "save-backups") }
        guard iCloud else { return folder.appending(path: "Save Backups") }
        return URL.libraryDirectory.appending(path: "Mobile Documents/com~apple~CloudDocs/Hangar/Save Backups")
    }

    /// Each Windows game's Wine log from its last launch: Wine Logs/ next to the library, or <store>-run/wine-logs.
    static var wineLogsFolder: URL {
        isOverridden ? runFile("wine-logs") : folder.appending(path: "Wine Logs")
    }

    /// Game details from the Steam store and TheGamesDB, cached: Details/ next to the library, or <store>-run/details.
    static var detailsFolder: URL {
        isOverridden ? runFile("details") : folder.appending(path: "Details")
    }

    /// A test run never asks the stores: it reads the sample answers (APP_FIXTURES/Details), or nothing.
    static var detailsFetch: GameDetailsCache.Fetch {
        guard isOverridden else { return CoverCache.download }
        let fixtures = ProcessInfo.processInfo.environment["APP_FIXTURES"] ?? "/nonexistent"
        return GameDetailsCache.folder(URL(fileURLWithPath: fixtures).appending(path: "Details"))
    }

    /// Where scans look. A test run never reads this Mac's games: it scans the sample library
    /// (APP_FIXTURES, copied to <store>-run/fixtures in /tmp) or nothing.
    static func roots(steamFolder: String?) -> LibraryRoots {
        guard isOverridden else { return .live(steamFolder: steamFolder) }
        let copy = runFile("fixtures")
        if let source = ProcessInfo.processInfo.environment["APP_FIXTURES"], !source.isEmpty {
            if FileManager.default.fileExists(atPath: copy.path) { return FixtureLibrary.roots(at: copy) }
            if let roots = try? FixtureLibrary.install(from: URL(fileURLWithPath: source), to: copy) { return roots }
        }
        return FixtureLibrary.roots(at: copy.appending(path: "none"))
    }
}
