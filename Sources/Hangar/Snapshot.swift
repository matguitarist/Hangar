import AppKit
import HangarKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/Hangar-test.json APP_SNAPSHOT=/tmp/shots ~/Applications/Hangar.app/Contents/MacOS/Hangar
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=library,game-page limits the pages (names in SnapshotPage.all). Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real library.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            if env["APP_SNAPSHOT_MIN"] != nil, let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) {
                // The window clamps to its content's minimum size.
                main.setContentSize(NSSize(width: 1, height: 1))
                try? await Task.sleep(for: .seconds(0.5))
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SnapshotPage.all where only?.contains(page.name) ?? true {
                    page.show(model)
                    try? await Task.sleep(for: .seconds(["add-game", "snapshots", "recipe-preview", "share-recipe", "backups"].contains(page.name) ? 1.2 : 0.8))
                    capture(to: "\(dir)/\(page.name)-\(mode).png")
                    if model.addRequest != nil || model.showsSnapshots != nil || model.previewingRecipe != nil || model.showsBackups != nil {
                        model.addRequest = nil
                        model.showsSnapshots = nil
                        model.showsBackups = nil
                        model.previewingRecipe = nil
                        try? await Task.sleep(for: .seconds(0.5))
                    }
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}

/// The pages snapshot mode shoots, with the state each one needs. Seed data (APP_SEED=1) fills them.
struct SnapshotPage {
    let name: String
    let show: @MainActor (AppModel) -> Void

    static func select(_ model: AppModel, _ title: String) {
        model.selectedGameID = model.library.games.first { $0.title.hasPrefix(title) }?.id
        model.showsGamePage = model.selectedGameID != nil
        model.gamePageTab = .overview
        model.scrollGamePageToEnd = false
    }

    static let all: [SnapshotPage] = [
        SnapshotPage(name: "library") { model in
            model.searchText = ""; model.sidebar = .allGames; model.selectedGameID = nil; model.showsGamePage = false
        },
        SnapshotPage(name: "game-page") { model in
            model.sidebar = .allGames; select(model, "Starfall Arcade")
        },
        SnapshotPage(name: "game-page-compatibility") { model in
            model.sidebar = .allGames; select(model, "Hollow Knight")
        },
        SnapshotPage(name: "game-page-windows") { model in
            model.sidebar = .allGames; select(model, "Vernal Edge")
        },
        SnapshotPage(name: "game-page-settings") { model in
            model.sidebar = .allGames; select(model, "Moonlit Harbor"); model.gamePageTab = .settings
            if let id = model.selectedGameID { model.setOptions(id) { $0.runner = nil } }
        },
        SnapshotPage(name: "game-page-settings-wine") { model in
            model.sidebar = .allGames; select(model, "Moonlit Harbor"); model.gamePageTab = .settings
            if let id = model.selectedGameID, let wine = model.runners.first(where: { $0.kind == .wine }) {
                model.setOptions(id) { $0.runner = wine.path }
            }
        },
        SnapshotPage(name: "game-page-settings-mac") { model in
            if let id = model.library.games.first(where: { $0.title == "Moonlit Harbor" })?.id { model.setOptions(id) { $0.runner = nil } }
            model.sidebar = .allGames; select(model, "Hollow Knight"); model.gamePageTab = .settings
            if let id = model.selectedGameID {
                model.setOptions(id) {
                    $0.arguments = "-windowed -novid"
                    $0.variables = [EnvironmentVariable(name: "DXVK_HUD", value: "fps,frametimes")]
                }
            }
        },
        SnapshotPage(name: "game-page-settings-shared") { model in
            // A bottle with other games in it, none of them running.
            model.running = [:]
            model.sidebar = .allGames; select(model, "Vernal Edge"); model.gamePageTab = .settings
        },
        SnapshotPage(name: "library-runner-update") { model in
            model.sidebar = .allGames; model.selectedGameID = nil; model.showsGamePage = false
            let ids = ["Vernal Edge", "Kynseed"].compactMap { title in model.library.games.first { $0.title == title }?.id }
            let snapshots: [SettingsSnapshot] = ids.compactMap { id in
                guard let game = model.game(id), let s = try? model.snapshots.take(game, bottle: nil, reason: .launch, runner: "CrossOver 26.2") else { return nil }
                try? model.snapshots.markWorked(s, on: Date().addingTimeInterval(-9 * 86400))
                return model.snapshots.list(id).first { $0.id == s.id }
            }
            model.runnerUpdates = [RunnerUpdateNotice(update: RunnerUpdate(name: "CrossOver", path: "/Applications/CrossOver.app", old: "26.2", new: "26.3"), snapshots: snapshots)]
        },
        SnapshotPage(name: "game-page-links") { model in
            model.runnerUpdates = []
            model.showsGamePage = true
            model.sidebar = .allGames; select(model, "Hollow Knight")
            model.scrollGamePageToEnd = true
        },
        SnapshotPage(name: "game-page-saves") { model in
            model.runnerUpdates = []
            model.showsGamePage = true
            model.sidebar = .allGames; select(model, "Hollow Knight")
            model.scrollGamePageToEnd = true
            if let id = model.selectedGameID, model.backupList(id).isEmpty {
                let saves = model.roots.home.appending(path: "Library/Application Support/unity.Team Cherry.Hollow Knight")
                _ = try? model.saveBackups.backUp(id, saves: [saves], reason: .launch, now: Date().addingTimeInterval(-26 * 3600))
                model.backupGeneration += 1
            }
        },
        SnapshotPage(name: "backups") { model in
            model.scrollGamePageToEnd = false
            if let id = model.selectedGameID, let saves = model.backupList(id).first?.items.first.map({ URL(fileURLWithPath: $0.source) }) {
                // A second, older backup, taken before a restore.
                if model.backupList(id).count < 2 {
                    try? Data("older".utf8).write(to: saves.appending(path: "user2.dat"))
                    _ = try? model.saveBackups.backUp(id, saves: [saves], reason: .beforeRestore, now: Date().addingTimeInterval(-5 * 86400))
                    model.backupGeneration += 1
                }
                model.showsBackups = id
            }
        },
        SnapshotPage(name: "game-page-crash") { model in
            model.scrollGamePageToEnd = false
            model.sidebar = .allGames; select(model, "Moonlit Harbor")
            if let id = model.selectedGameID, let fixtures = ProcessInfo.processInfo.environment["APP_FIXTURES"] {
                try? FileManager.default.createDirectory(at: Store.wineLogsFolder, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: model.wineLogURL(id))
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: fixtures).appending(path: "WineLogs/missing-vcrun.log"), to: model.wineLogURL(id))
                model.readCrash(id)
            }
        },
        SnapshotPage(name: "share-recipe") { model in
            if let id = model.library.games.first(where: { $0.title == "Moonlit Harbor" })?.id { model.notices[id] = nil }
            model.scrollGamePageToEnd = false
            model.runnerUpdates = []
            model.showsGamePage = true
            model.sidebar = .allGames; select(model, "Kynseed")
            model.gamePageTab = .settings
            model.sharingRecipe = model.selectedGameID
        },
        SnapshotPage(name: "game-page-recipe") { model in
            model.sharingRecipe = nil
            model.runnerUpdates = []
            model.showsGamePage = true
            model.sidebar = .allGames; select(model, "Moonlit Harbor")
        },
        SnapshotPage(name: "recipe-preview") { model in
            model.sidebar = .allGames; select(model, "Moonlit Harbor")
            model.previewingRecipe = model.selectedGameID
        },
        SnapshotPage(name: "game-page-worked") { model in
            model.previewingRecipe = nil
            model.sidebar = .allGames; select(model, "Hollow Knight")
            if let id = model.selectedGameID { model.notices[id] = .askWorked }
        },
        SnapshotPage(name: "snapshots") { model in
            model.sidebar = .allGames; select(model, "Kynseed")
            guard let id = model.selectedGameID, model.snapshotList(id).isEmpty, let game = model.game(id), var settings = model.bottleSettings(for: game) else {
                model.showsSnapshots = model.selectedGameID
                return
            }
            if let worked = model.takeSnapshot(id, reason: .launch) { try? model.snapshots.markWorked(worked, on: Date().addingTimeInterval(-11 * 86400)) }
            settings.graphics = .dxvk
            model.running = [:]
            model.changeBottleSettings(id, to: settings)
            settings.msync = false
            model.changeBottleSettings(id, to: settings)
            model.showsSnapshots = id
        },
        SnapshotPage(name: "game-page-running") { model in
            model.showsSnapshots = nil
            if model.running.isEmpty, let game = model.library.games.first(where: { $0.title.hasPrefix("Bloodstained") }) {
                model.running[game.id] = LaunchState(phase: .running, launched: Date().addingTimeInterval(-1200), started: Date().addingTimeInterval(-1190))
            }
            model.sidebar = .running; select(model, "Bloodstained")
        },
        SnapshotPage(name: "steam") { model in
            model.sidebar = .source(.steam); model.selectedGameID = nil; model.showsGamePage = false
        },
        SnapshotPage(name: "crossover") { model in
            model.sidebar = .source(.crossOver); model.selectedGameID = nil; model.showsGamePage = false
        },
        SnapshotPage(name: "collection") { model in
            if let first = model.library.collections.first { model.sidebar = .collection(first.id) }
        },
        SnapshotPage(name: "empty-collection") { model in
            if let last = model.library.collections.last { model.sidebar = .collection(last.id) }
        },
        SnapshotPage(name: "no-match") { model in
            model.sidebar = .allGames; model.searchText = "xyz"
        },
        SnapshotPage(name: "add-game") { model in
            model.searchText = ""
            let exe = model.roots.bottles.appending(path: "Classics/drive_c/Program Files/Moonlit Harbor/MoonlitHarbor.exe")
            model.addRequest = AddRequest(file: exe)
        },
        SnapshotPage(name: "runners") { model in
            model.sidebar = .runners
            model.runners = RunnerScanner.scan(model.roots)
        },
        SnapshotPage(name: "runners-none") { model in
            model.sidebar = .runners
            model.runners = []
        },
        SnapshotPage(name: "log") { model in
            model.sidebar = .log
        },
    ]
}
