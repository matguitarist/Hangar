import AppKit
import AppTestKit
import HangarKit
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
        // Refuses and quits without APP_STORE in /tmp: snapshots never run against the real library.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            await run.start()
            let sheets: Set<String> = ["add-game", "snapshots", "recipe-preview", "share-recipe", "backups"]
            await run.shootPages(SnapshotPage.all.map(\.name), settle: { sheets.contains($0) ? .seconds(1.2) : nil }) { name in
                // A sheet the page before opened closes first, so it is gone from this shot.
                if model.addRequest != nil || model.showsSnapshots != nil || model.previewingRecipe != nil || model.showsBackups != nil {
                    model.addRequest = nil
                    model.showsSnapshots = nil
                    model.showsBackups = nil
                    model.previewingRecipe = nil
                    await run.pause(.seconds(0.5))
                }
                if !name.hasPrefix("couch") { model.leaveCouchMode() }
                SnapshotPage.all.first { $0.name == name }?.show(model)
            }
            if run.wants("menu-bar") {
                // The menu bar panel, drawn in a panel of its own: the real one opens only from a click.
                let host = NSHostingView(rootView: QuickLaunchView(close: {})
                    .environment(model).themed()
                    .background(.background, in: .rect(cornerRadius: Radius.card, style: .continuous)))
                let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                                    backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.contentView = host
                panel.setContentSize(host.fittingSize)
                panel.center()
                await run.forEachAppearance { look in
                    panel.orderFront(nil)
                    await run.pause(.seconds(1))
                    await run.capture("menu-bar", look, window: panel)
                }
                panel.close()
            }
            await run.shoot("whats-new", window: { WindowShot.mainWindow()?.attachedSheet },
                           show: { WhatsNewState.shared.shown = .sample }, hide: { WhatsNewState.shared.shown = nil })
            // The Settings window is the front titled window that isn't the main one or a panel (the menu bar icon has one).
            await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                    select: { model.settingsTab = SettingsTab(rawValue: $0) ?? .general })
            run.finish()
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
        SnapshotPage(name: "game-page-suggested") { model in
            model.scrollGamePageToEnd = false
            model.sidebar = .allGames; select(model, "Vernal Edge"); model.gamePageTab = .overview
            // Settings the wiki's notes disagree with (on the test copy), so the card shows.
            // Written straight to the test copy: Bloodstained runs in the same bottle, so Apply shows disabled.
            if let id = model.selectedGameID, let bottle = model.game(id)?.bottle {
                _ = try? BottleSettings(graphics: .dxvk).write(bottle: model.bottleURL(bottle))
                model.suggestionState[id] = nil
            }
        },
        SnapshotPage(name: "game-page-battery") { model in
            model.sidebar = .allGames; select(model, "Pocket Racer"); model.gamePageTab = .settings
            if let id = model.selectedGameID { model.useBatteryProfile(id, true) }
        },
        SnapshotPage(name: "game-page-low-power") { model in
            model.gamePageTab = .overview
            if let id = model.selectedGameID { model.useBatteryProfile(id, false); model.notices[id] = .lowPowerModeOff }
        },
        SnapshotPage(name: "game-page-mac-version") { model in
            if let id = model.library.games.first(where: { $0.title == "Pocket Racer" })?.id { model.notices[id] = nil }
            model.sidebar = .allGames; select(model, "Starfall Arcade")
        },
        SnapshotPage(name: "game-page-windows") { model in
            model.sidebar = .allGames; select(model, "Vernal Edge")
        },
        SnapshotPage(name: "game-page-settings") { model in
            model.sidebar = .allGames; select(model, "Moonlit Harbor"); model.gamePageTab = .settings
            if let id = model.selectedGameID { model.setOptions(id) { $0.runner = nil } }
        },
        SnapshotPage(name: "game-page-frame-rate") { model in
            model.sidebar = .allGames; select(model, "Moonlit Harbor"); model.gamePageTab = .settings
            model.running = [:]
            if let id = model.selectedGameID, let game = model.game(id), var settings = model.bottleSettings(for: game) {
                model.setOptions(id) { $0.runner = nil; $0.frameCap = 40 }
                settings.graphics = .dxvk
                model.changeBottleSettings(id, to: settings)
            }
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
            model.running = [:]
            let ids = ["Vernal Edge", "Kynseed"].compactMap { title in model.library.games.first { $0.title == title }?.id }
            let snapshots: [SettingsSnapshot] = ids.compactMap { id in
                guard let game = model.game(id),
                      let s = try? model.snapshots.take(game, bottle: game.bottle.map(model.bottleURL), reason: .launch, runner: "CrossOver 26.2") else { return nil }
                try? model.snapshots.markWorked(s, on: Date().addingTimeInterval(-9 * 86400))
                return model.snapshots.list(id).first { $0.id == s.id }
            }
            var drifts: [BottleDrift] = []
            if let snapshot = snapshots.first(where: { model.snapshots.bottleSettings(in: $0) != nil }), let bottle = snapshot.bottle {
                let was = model.snapshots.bottleSettings(in: snapshot) ?? BottleSettings()
                var now = was
                now.graphics = was.graphics == .auto ? .d3dMetal : .auto
                now.msync.toggle()
                drifts = [BottleDrift(bottle: bottle, snapshot: snapshot, was: was, now: now)]
            }
            model.runnerUpdates = [RunnerUpdateNotice(update: RunnerUpdate(name: "CrossOver", path: "/Applications/CrossOver.app", old: "26.2", new: "26.3"),
                                                      snapshots: snapshots, drifts: drifts)]
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
        SnapshotPage(name: "fetch-details") { model in
            model.scrollGamePageToEnd = false
            model.showsGamePage = false
            model.sidebar = .allGames
            model.detailsRun = DetailsRun(total: 10, done: 4, found: 3)
        },
        SnapshotPage(name: "share-recipe") { model in
            model.detailsRun = nil
            model.showsGamePage = true
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
        SnapshotPage(name: "game-page-sign-in") { model in
            model.sidebar = .allGames; select(model, "Vernal Edge")
            if let id = model.selectedGameID { model.notices[id] = .signInFirst("Steam") }
        },
        SnapshotPage(name: "heroic") { model in
            if let id = model.library.games.first(where: { $0.title == "Vernal Edge" })?.id { model.notices[id] = nil }
            model.sidebar = .source(.heroic); model.selectedGameID = nil; model.showsGamePage = false
        },
        SnapshotPage(name: "game-page-heroic") { model in
            model.sidebar = .source(.heroic); select(model, "Ember Isles"); model.gamePageTab = .settings
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
        SnapshotPage(name: "game-page-playtime") { model in
            model.filter = nil
            model.sidebar = .allGames; select(model, "Kynseed"); model.gamePageTab = .overview; model.showsGamePage = true
            if let id = model.selectedGameID, let index = model.library.games.firstIndex(where: { $0.id == id }) {
                // Twelve weeks of evenings, more on weekends.
                let now = Date()
                var sessions: [PlaySession] = []
                for day in stride(from: 83, through: 0, by: -1) where day % 3 != 1 {
                    let start = now.addingTimeInterval(-Double(day) * 86400 - 3 * 3600)
                    sessions.append(PlaySession(start: start, length: Double(1800 + (day * 977) % 5400)))
                }
                model.library.games[index].sessions = sessions
                model.library.games[index].playtime = sessions.map(\.length).reduce(0, +)
                model.library.games[index].lastPlayed = sessions.last.map { $0.start.addingTimeInterval($0.length) }
            }
            model.scrollGamePageToEnd = true
        },
        SnapshotPage(name: "library-last-launch") { model in
            model.scrollGamePageToEnd = false
            model.sidebar = .allGames; select(model, "Pocket Racer"); model.gamePageTab = .overview; model.showsGamePage = true
            for (title, outcome, played) in [("Pocket Racer", LaunchRecord.Outcome.quitRightAway, 1.0), ("Moonlit Harbor", .crashed, 4.0), ("Kynseed", .worked, 3600.0)] {
                if let index = model.library.games.firstIndex(where: { $0.title == title }) {
                    for _ in 0..<11 { model.library.games[index].record(.worked, played: 1800) }
                    model.library.games[index].record(outcome, played: played)
                }
            }
        },
        SnapshotPage(name: "library-import") { model in
            model.sidebar = .allGames; model.selectedGameID = nil; model.showsGamePage = false
            model.lastImportUndo = model.library
            model.importMessage = String(localized: "Imported \(model.library.games.count) games and \(model.library.collections.count) collections.")
        },
        SnapshotPage(name: "library-filter") { model in
            model.importMessage = nil; model.lastImportUndo = nil
            model.scrollGamePageToEnd = false
            model.sidebar = .allGames; model.selectedGameID = nil; model.showsGamePage = false; model.runnerUpdates = []
            model.filter = .neverPlayed
        },
        SnapshotPage(name: "library-filter-empty") { model in
            model.sidebar = .source(.heroic); model.filter = .mac
        },
        SnapshotPage(name: "health") { model in
            model.filter = nil
            model.sidebar = .health
        },
        SnapshotPage(name: "storage") { model in
            let old = model.roots.prefixes.appending(path: "Old Game-1a2b")
            try? FileManager.default.createDirectory(at: old.appending(path: "drive_c"), withIntermediateDirectories: true)
            try? Data(repeating: 7, count: 3_000_000).write(to: old.appending(path: "drive_c/big.bin"))
            model.storageItems = nil
            model.sidebar = .storage
        },
        SnapshotPage(name: "log") { model in
            model.sidebar = .log
        },
        SnapshotPage(name: "couch") { model in
            model.leaveCouchMode()
            model.sidebar = .allGames; select(model, "Hollow Knight"); model.showsGamePage = false
            model.enterCouchMode()
        },
        SnapshotPage(name: "couch-details") { model in
            model.couch(.details)
        },
    ]
}
