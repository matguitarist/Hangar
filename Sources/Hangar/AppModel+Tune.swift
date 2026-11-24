import Foundation
import HangarKit

/// The game page's Settings tab: bottle settings, and later launch options and runners.
enum GamePageTab: String, CaseIterable {
    case overview, settings

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .settings: String(localized: "Settings")
        }
    }
}

extension AppModel {
    func bottleURL(_ name: String) -> URL { roots.bottles.appending(path: name) }

    /// The bottle settings of a Windows game in a CrossOver bottle, read from its files.
    func bottleSettings(for game: Game) -> BottleSettings? {
        guard game.runner == .crossOver, let bottle = game.bottle else { return nil }
        return BottleSettings.read(bottle: bottleURL(bottle))
    }

    /// True while a game in the bottle runs: Wine would write over a changed registry when it quits.
    func bottleIsBusy(_ name: String) -> Bool {
        running.keys.contains { game($0)?.bottle == name }
    }

    /// Writes a bottle's settings, for a game's Settings tab.
    func changeBottleSettings(_ id: String, to settings: BottleSettings) {
        guard let game = game(id), let bottle = game.bottle, !bottleIsBusy(bottle) else { return }
        do {
            let changed = try settings.write(bottle: bottleURL(bottle))
            if !changed.isEmpty {
                log.post(.info, "Changed the settings of the bottle \(bottle) for \(game.title): graphics \(settings.graphics.title), MSync \(settings.msync), high resolution \(settings.highResolution), MetalFX \(settings.metalFX), AVX \(settings.avx)", source: "Settings")
            }
        } catch {
            log.post(.error, "Can't change the settings of the bottle \(bottle): \(error.localizedDescription)", source: "Settings")
        }
        settingsGeneration += 1
    }
}
