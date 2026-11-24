import AppKit
import Foundation
import HangarKit

/// Where games save (S-021), from PCGamingWiki, found on this Mac.
extension AppModel {
    /// The folders a game's paths stand for: its bottle or prefix for a Windows game, the home folder for a Mac game.
    func savePathContext(_ game: Game) -> SavePathContext {
        var driveC: URL?
        if let path = game.options.runner, game.runner == .crossOver, game.steamID == nil, !path.isEmpty {
            driveC = LaunchPlanner.prefix(for: game, roots: roots).appending(path: "drive_c")
        } else if game.isWindows, let bottle = game.bottle {
            driveC = bottleURL(bottle).appending(path: "drive_c")
        }
        let steam: URL? = game.steamID == nil ? nil
            : driveC.map { $0.appending(path: "Program Files (x86)/Steam") } ?? roots.steam
        return SavePathContext(userProfile: driveC.map { SavePathContext.userProfile(driveC: $0) }, driveC: driveC,
                               home: roots.home, game: game.path.isEmpty ? nil : URL(fileURLWithPath: game.path), steam: steam)
    }

    /// Reads PCGamingWiki (or its cache) for where a game saves, then looks for those folders.
    /// `force` looks on disk again (after a launch made the first save).
    func loadSaveLocations(_ id: String, force: Bool = false) async {
        guard force || saveLocations[id] == nil, let game = game(id) else { return }
        guard let data = await gameDataCache.data(for: game.title) else {
            saveLocations[id] = .some(nil)
            return
        }
        saveDataPages[id] = data.url
        saveLocations[id] = .some(SavePaths.locations(data, isWindows: game.isWindows, onSteam: game.steamID != nil,
                                                      context: savePathContext(game)))
    }

    /// The save locations already loaded, or an empty list.
    func knownSaveLocations(_ id: String) -> [SaveLocation] {
        (saveLocations[id] ?? nil) ?? []
    }

    /// Show in Finder for a save or settings location. A test run records it instead.
    func showSaveLocation(_ location: SaveLocation) {
        let target = location.exists ? (location.found.count == 1 && !location.path.contains("*") ? location.found[0] : location.folder) : location.folder
        if Store.isOverridden { openedURLs.append(target); return }
        if location.exists {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            // Not there yet: open the nearest folder that is.
            var folder = target
            while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 { folder.deleteLastPathComponent() }
            NSWorkspace.shared.open(folder)
        }
    }
}
