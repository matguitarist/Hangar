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
    }
}
