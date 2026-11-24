import Foundation
import HangarKit

/// M4 (Saves and crashes) checks, on the sample library.
extension SelfTest {
    static func savesChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        func find(_ title: String) -> Game? { model.library.games.first { $0.title == title } }

        // S-021
        if let vernal = find("Vernal Edge") {
            await model.loadSaveLocations(vernal.id)
            let locations = model.knownSaveLocations(vernal.id)
            check("S-021 a Windows game's saves are found inside its bottle",
                  locations.first?.kind == .saves && locations.first?.exists == true
                    && locations.first?.folder.path.hasSuffix("/drive_c/users/crossover/AppData/Local/VernalEdge/Saved/SaveGames") == true
                    && locations.first?.folder.path.hasPrefix(model.bottleURL(vernal.bottle ?? "").path) == true,
                  locations.first?.path ?? "none")
            if let saves = locations.first {
                model.openedURLs = []
                model.showSaveLocation(saves)
                check("S-021 Show in Finder opens the sample game's save folder", model.openedURLs.last?.lastPathComponent == "SaveGames",
                      model.openedURLs.last?.path ?? "nothing opened")
            }
        } else {
            check("S-021 Vernal Edge is in the sample library", false)
        }
        if let knight = find("Hollow Knight") {
            await model.loadSaveLocations(knight.id)
            let saves = model.knownSaveLocations(knight.id).first
            check("S-021 a Mac game's saves are found in the home folder", saves?.exists == true
                  && saves?.folder.lastPathComponent == "unity.Team Cherry.Hollow Knight", saves?.path ?? "none")
        }

        // S-022: Starfall Arcade was played several times by the checks before, its saves never changing.
        if let starfall = find("Starfall Arcade") {
            check("S-022 launching the sample game made one backup, and unchanged saves made no more",
                  model.backupList(starfall.id).count == 1, "\(model.backupList(starfall.id).count) backups")
            let save = model.roots.home.appending(path: "Library/Application Support/Starfall Arcade/Saves/profile.sav")
            try? Data("level 4\n".utf8).write(to: save)
            _ = await launched(model, starfall.id)
            let backups = model.backupList(starfall.id)
            check("S-022 a launch after the saves changed makes a new backup", backups.count == 2, "\(backups.count) backups")
            let stored = backups.first.map { model.saveBackups.location(of: $0, gameID: starfall.id) }
            let copy = stored.flatMap { try? String(contentsOf: $0.appending(path: "items/0/Saves/profile.sav"), encoding: .utf8) }
            check("S-022 the backup holds the save as it was before the game started", copy == "level 4\n", copy ?? "missing")
            model.backupsInICloud = true
            check("S-022 iCloud Drive keeps the backups when turned on", model.backupList(starfall.id).count == 2
                  && model.saveBackups.root.lastPathComponent == "icloud-save-backups")
            model.backupsInICloud = false
            check("S-022 and they come back when turned off", model.backupList(starfall.id).count == 2)

            // S-023: back to the save from before "level 4".
            try? Data("level 5\n".utf8).write(to: save)
            if let old = backups.last {
                await model.restoreBackup(old, gameID: starfall.id)
                let now = try? String(contentsOf: save, encoding: .utf8)
                check("S-023 restore puts the old save back", now == "level 3\n", now ?? "missing")
                let after = model.backupList(starfall.id)
                check("S-023 the current save shows as a new backup", after.count == 3 && after.first?.reason == .beforeRestore)
                let kept = after.first.flatMap { try? String(contentsOf: model.saveBackups.location(of: $0, gameID: starfall.id)
                    .appending(path: "items/0/Saves/profile.sav"), encoding: .utf8) }
                check("S-023 that backup holds the save that was replaced", kept == "level 5\n", kept ?? "missing")
            }
        }

        // S-031
        if let knight = find("Hollow Knight"), let moonlit = find("Moonlit Harbor") {
            await model.loadDetails(knight.id)
            let steam = model.details[knight.id] ?? nil
            check("S-031 a Steam game's details come from the Steam store", steam?.source == .steam && steam?.developers == ["Team Cherry"]
                  && steam?.genres.contains("Action") == true, String(describing: steam?.developers))
            await model.loadDetails(moonlit.id)
            check("S-031 without a TheGamesDB key, a game that isn't on Steam has none", model.details[moonlit.id] == .some(nil))
            model.theGamesDBKey = " test-key "
            check("S-031 the TheGamesDB key is kept (in memory in a test run)", Keychain.read("thegamesdb") == "test-key")
            for _ in 0..<20 where model.details[moonlit.id] != nil { try? await Task.sleep(for: .milliseconds(50)) }
            await model.loadDetails(moonlit.id)
            let other = model.details[moonlit.id] ?? nil
            check("S-031 with the key, it's found on TheGamesDB with its names", other?.source == .theGamesDB
                  && other?.developers == ["Tidewater Games"] && other?.genres == ["Adventure", "Puzzle"], String(describing: other))
            model.theGamesDBKey = ""
            check("S-031 clearing the key forgets it", Keychain.read("thegamesdb") == nil)
        }

        // S-032
        if let knight = find("Hollow Knight") {
            model.fetchAllDetails()
            check("S-032 Fetch All Details shows its progress", model.detailsRun?.total == model.library.games.count && MenuState.shared.isFetchingDetails)
            for _ in 0..<200 where model.detailsRun?.finished != true { try? await Task.sleep(for: .milliseconds(50)) }
            let run = model.detailsRun
            check("S-032 and goes through every game", run?.finished == true && run?.done == run?.total && (run?.found ?? 0) >= 1
                  && !MenuState.shared.isFetchingDetails, String(describing: run))
            model.details[knight.id] = .some(nil)
            await model.loadDetails(knight.id, force: true)
            check("S-032 Refresh Details asks again", (model.details[knight.id] ?? nil)?.developers == ["Team Cherry"])
            model.detailsRun = nil
        }

        // S-033: Vernal Edge's wiki page has no native verdict, but Steam sells a Mac version;
        // Starfall Arcade has no wiki page, but is on the Mac App Store.
        if let vernal = find("Vernal Edge"), let starfall = find("Starfall Arcade") {
            await model.loadCompatibility(vernal.id)
            await model.loadDetails(vernal.id)
            check("S-033 Steam's Mac version shows when the wiki has no native verdict", model.macVersions(vernal).steam)
            await model.loadAppStore(starfall.id)
            let app = model.macVersions(starfall).appStore
            check("S-033 a game on the Mac App Store is found by its name", app?.name == "Starfall Arcade", String(describing: app))
            model.openedURLs = []
            if let app { model.open(app.url) }
            check("S-033 Open in the App Store opens its page", model.openedURLs.last?.host() == "apps.apple.com")
        }

        // S-024: Moonlit Harbor, a program in the Classics bottle, with sample Wine logs.
        if let moonlit = find("Moonlit Harbor"), let fixtures = ProcessInfo.processInfo.environment["APP_FIXTURES"] {
            let logs = URL(fileURLWithPath: fixtures).appending(path: "WineLogs")
            func crash(with log: String) {
                try? FileManager.default.createDirectory(at: Store.wineLogsFolder, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: model.wineLogURL(moonlit.id))
                try? FileManager.default.copyItem(at: logs.appending(path: log), to: model.wineLogURL(moonlit.id))
                model.readCrash(moonlit.id)
            }
            crash(with: "missing-vcrun.log")
            guard case let .crashed(reason) = model.notices[moonlit.id], let reason else {
                return check("S-024 a sample crash log shows its reason", false, String(describing: model.notices[moonlit.id]))
            }
            check("S-024 a sample crash log shows its reason", reason.kind == .missingRuntime(.visualCpp), reason.title)
            let fix = model.crashFix(moonlit, reason)
            check("S-024 and the fix button", fix == .openCrossOver)
            model.openedURLs = []
            if let fix { model.apply(fix, to: moonlit.id) }
            check("S-024 the fix opens CrossOver", model.openedURLs.last?.lastPathComponent == "CrossOver.app")
            crash(with: "d3d11.log")
            if case let .crashed(.some(d3d)) = model.notices[moonlit.id], let fix = model.crashFix(moonlit, d3d) {
                check("S-024 a Direct3D 11 failure offers DXVK", fix == .useGraphics(.dxvk))
                let before = model.snapshotList(moonlit.id).count
                model.apply(fix, to: moonlit.id)
                check("S-024 Use DXVK changes the bottle after a snapshot",
                      model.bottleSettings(for: moonlit)?.graphics == .dxvk && model.snapshotList(moonlit.id).count == before + 1)
            } else {
                check("S-024 a Direct3D 11 failure offers DXVK", false, String(describing: model.notices[moonlit.id]))
            }
            crash(with: "clean.log")
            check("S-024 a log with no known line says so", model.notices[moonlit.id] == .crashed(nil))
            model.notices[moonlit.id] = nil
        }
    }
}
