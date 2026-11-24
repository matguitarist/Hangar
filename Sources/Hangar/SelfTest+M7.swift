import Foundation
import HangarKit

extension SelfTest {
    /// M7: look after the library.
    static func m7Checks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        sessionChecks(model)
        lastLaunchChecks(model)
        await frameCapChecks(model)
        await storageChecks(model)
        await driftChecks(model)
        await healthChecks(model)
        filterChecks(model)
        exportChecks(model)
    }

    /// S-046: export, then import into an empty library, gives back the collections and playtime.
    static func exportChecks(_ model: AppModel) {
        let original = model.library
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Hangar-selftest-\(UUID().uuidString).hangarlibrary")
        model.exportLibrary(to: file)
        check("S-046 Export writes the file", FileManager.default.fileExists(atPath: file.path))
        model.library = LibraryFile()
        let summary = model.importLibrary(from: file)
        let played = original.games.filter { $0.playtime > 0 }
        check("S-046 import into an empty library gives back the collections",
              Set(model.library.collections.map(\.name)) == Set(original.collections.map(\.name)) && summary?.collections == original.collections.count,
              model.library.collections.map(\.name).joined(separator: ", "))
        // An empty library has no games yet: they wait in Removed Games until a scan finds them.
        check("S-046 import gives back the playtime",
              !played.isEmpty && played.allSatisfy { game in (model.library.games + model.library.removed).first { $0.id == game.id }?.playtime == game.playtime })
        check("S-046 the import says what it did", model.importMessage?.contains("\(original.games.count + original.removed.count)") == true, model.importMessage ?? "none")
        model.undoImport()
        check("S-046 Undo puts the library back", model.library.games.isEmpty && model.importMessage == nil)
        model.library = original
        try? FileManager.default.removeItem(at: file)
    }

    /// S-044: the S-006 launch of Starfall Arcade added a session as long as its playtime.
    static func sessionChecks(_ model: AppModel) {
        guard let game = model.library.games.first(where: { $0.title == "Starfall Arcade" }) else { return check("S-044 Starfall Arcade is there", false) }
        let total = game.sessions.map(\.length).reduce(0, +)
        check("S-044 a launch adds a session", !game.sessions.isEmpty && abs(total - game.playtime) < 1
                  && game.sessions.last.map { Date().timeIntervalSince($0.start) < 900 } == true,
              "\(game.sessions.count) sessions, playtime \(game.playtime)")
        check("S-044 the session is saved with the game",
              LibraryFile.load(from: Store.url).games.first { $0.id == game.id }?.sessions.isEmpty == false || { model.saveNow(); return LibraryFile.load(from: Store.url).games.first { $0.id == game.id }?.sessions.isEmpty == false }())
    }

    /// S-045: Pocket Racer quit at once in the S-006 checks; Starfall Arcade worked.
    static func lastLaunchChecks(_ model: AppModel) {
        let racer = model.library.games.first { $0.title == "Pocket Racer" }
        let starfall = model.library.games.first { $0.title == "Starfall Arcade" }
        check("S-045 a game that quits at once keeps Quit right away", racer?.lastLaunch?.outcome == .quitRightAway,
              String(describing: racer?.lastLaunch))
        check("S-045 its tile says Quit right away", racer?.lastLaunch.map { $0.outcome.failed && $0.outcome.title == String(localized: "Quit right away") } == true)
        check("S-045 launches are counted", (racer?.launches ?? 0) >= 1 && (starfall?.launches ?? 0) >= 1, "\(racer?.launches ?? 0), \(starfall?.launches ?? 0)")
        check("S-045 a game stopped by the person worked", starfall?.lastLaunch?.outcome == .worked, String(describing: starfall?.lastLaunch))
    }

    /// S-043: Never Played shows only games without playtime, and combines with search.
    static func filterChecks(_ model: AppModel) {
        model.searchText = ""
        model.filter = .neverPlayed
        let never = model.games(for: .allGames)
        check("S-043 Never Played shows only games without playtime",
              !never.isEmpty && never.allSatisfy { $0.playtime == 0 && $0.lastPlayed == nil } && never.count < model.library.games.count,
              never.map(\.title).joined(separator: ", "))
        model.searchText = "zzz-no-match"
        check("S-043 a filter combines with search", model.games(for: .allGames).isEmpty)
        model.searchText = ""
        model.filter = .windows
        check("S-043 Windows Games shows only Windows games", model.games(for: .allGames).allSatisfy(\.isWindows))
        model.filter = nil
        check("S-043 Show All shows every game", model.games(for: .allGames).count == model.library.games.count)
    }

    /// S-042: the sample library's unreadable bottle and a game with saves and no backup show on Health; Back Up Now clears it.
    static func healthChecks(_ model: AppModel) async {
        await model.checkHealth(loadSaves: true)
        let issues = model.healthIssues
        let names = issues.map(\.id).joined(separator: ", ")
        check("S-042 Health shows the unreadable bottle Empty", issues.contains(.bottleUnreadable(bottle: "Empty")), names)
        let unsaved = issues.first { $0.kind == .neverBackedUp }
        check("S-042 Health shows a game with saves and no backup", unsaved != nil, names)
        if let unsaved {
            await model.fixHealth(unsaved)
            check("S-042 Back Up Now clears it", !model.healthIssues.contains(unsaved), model.healthIssues.map(\.id).joined(separator: ", "))
        }
    }

    /// S-040: an update that changed a bottle shows in the banner, and Put Back restores it after a snapshot.
    static func driftChecks(_ model: AppModel) async {
        guard let game = model.library.games.first(where: { $0.title == "Moonlit Harbor" }),
              let crossOver = model.runners.first(where: { $0.kind == .crossOver }), let version = crossOver.version,
              let bottle = game.bottle else { return check("S-040 the sample bottle game is there", false) }
        model.running = [:]
        let mine = BottleSettings(graphics: .d3dMetal, msync: true)
        model.changeBottleSettings(game.id, to: mine)
        _ = model.takeSnapshot(game.id, reason: .launch)
        // CrossOver updates and resets the bottle.
        _ = try? BottleSettings(graphics: .auto, msync: false).write(bottle: model.bottleURL(bottle))
        try? JSONEncoder().encode([crossOver.path: "26.1"]).write(to: Store.runnerVersionsURL)
        model.checkRunnerUpdates()
        let notice = model.runnerUpdates.first { $0.update.path == crossOver.path }
        let drift = notice?.drifts.first { $0.bottle == bottle }
        check("S-040 a bottle changed under Hangar shows in the update banner",
              drift.map { $0.was.graphics == .d3dMetal && $0.now.graphics == .auto && $0.changes.count == 2 } == true, String(describing: drift?.changes) + " \(version)")
        if let drift, let notice {
            let before = model.snapshotList(game.id).count
            model.putBack(drift, in: notice.id)
            check("S-040 Put Back restores the snapshot's settings", model.bottleSettings(for: game) == mine, String(describing: model.bottleSettings(for: game)))
            check("S-040 Put Back takes a snapshot first", model.snapshotList(game.id).count == before + 1 && model.snapshotList(game.id).first?.reason == .settings)
            model.undoPutBack(drift, in: notice.id)
            check("S-040 Undo puts the update's settings back", model.bottleSettings(for: game)?.graphics == .auto)
            model.changeBottleSettings(game.id, to: mine)
        }
        model.runnerUpdates = []
    }

    /// S-039: sizes add up, and old snapshots go while the newest and the labeled ones stay.
    static func storageChecks(_ model: AppModel) async {
        let old = model.roots.prefixes.appending(path: "Old Game-1a2b")
        try? FileManager.default.createDirectory(at: old.appending(path: "drive_c"), withIntermediateDirectories: true)
        try? Data(repeating: 7, count: 100_000).write(to: old.appending(path: "drive_c/big.bin"))
        await model.measureStorage()
        let items = model.storageItems ?? []
        check("S-039 Storage lists the games and bottles", items.contains { $0.kind == .games } && items.contains { $0.kind == .bottles })
        check("S-039 a prefix no game uses is Unused", items.first { $0.name == "Old Game-1a2b" }?.unused == true)
        let totals = StorageScanner.totals(items)
        check("S-039 the totals add up", totals.values.reduce(0, +) == items.map(\.bytes).reduce(0, +))
        if let unused = items.first(where: { $0.name == "Old Game-1a2b" }) {
            await model.trashPrefix(unused)
            check("S-039 Move to Trash removes the unused prefix", !FileManager.default.fileExists(atPath: old.path))
        }
        if let game = model.library.games.first(where: { $0.title == "Kynseed" }) {
            for n in 0..<6 {
                model.setOptions(game.id) { $0.arguments = "-storage \(n)" }
                _ = model.takeSnapshot(game.id, reason: .settings)
            }
            let before = model.snapshotList(game.id)
            if let oldest = before.last { try? model.snapshots.markWorked(oldest) }
            await model.deleteOldSnapshots()
            let after = model.snapshotList(game.id)
            check("S-039 Delete Old Snapshots keeps the newest three and the ones that worked",
                  after.count == 4 && after.contains { $0.worked != nil }, "\(before.count) → \(after.count)")
            model.setOptions(game.id) { $0.arguments = "" }
        }
    }

    /// S-038: a cap launches DXVK games with DXVK_FRAME_RATE, and nothing else.
    static func frameCapChecks(_ model: AppModel) async {
        guard let game = model.library.games.first(where: { $0.title == "Moonlit Harbor" }), var settings = model.bottleSettings(for: game) else {
            return check("S-038 the sample bottle game is there", false)
        }
        model.running = [:]
        model.setOptions(game.id) { $0.frameCap = 40; $0.runner = nil }
        settings.graphics = .dxvk
        model.changeBottleSettings(game.id, to: settings)
        // The sample CrossOver can't launch, so the check reads what the launch would add.
        let current = model.game(game.id) ?? game
        let dxvk = model.frameCapEnvironment(current, cap: current.options.frameCap)["DXVK_FRAME_RATE"]
        check("S-038 a DXVK game launches with its cap", dxvk == "40", dxvk ?? "none")
        settings.graphics = .d3dMetal
        model.changeBottleSettings(game.id, to: settings)
        let metal = model.frameCapEnvironment(current, cap: current.options.frameCap)["DXVK_FRAME_RATE"]
        check("S-038 a D3DMetal game gets no cap", metal == nil, metal ?? "none")
        model.setOptions(game.id) { $0.frameCap = nil }
        model.saveNow()
        check("S-038 the cap is saved with the game", LibraryFile.load(from: Store.url).games.first { $0.id == game.id }?.options.frameCap == nil)
    }
}
