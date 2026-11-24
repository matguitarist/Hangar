import AppKit
import LogKit
import SwiftUI
import HangarKit

// Hangar
//   Hangar                          the app, with the library in ~/Library/Application Support/Hangar
//   APP_STORE=<file> Hangar         a test run: the library in <file>, its log next to it; never reads or launches real games
//   APP_SNAPSHOT=<dir> Hangar       save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Hangar               with APP_STORE: sample data for snapshots (tools/snap.sh)
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
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }

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
}
