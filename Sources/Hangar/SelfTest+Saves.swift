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
    }
}
