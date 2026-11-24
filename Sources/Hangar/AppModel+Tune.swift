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

    /// The other games in a game's bottle, which a settings change would change too.
    func bottleMates(of game: Game) -> [Game] {
        guard let bottle = game.bottle, game.runner == .crossOver else { return [] }
        return library.games.filter { $0.id != game.id && $0.bottle == bottle && $0.source == .crossOver }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Copies a game's bottle and moves the game to the copy, so its settings change it alone.
    /// The other games found in the copy stay out of the library (Settings › Removed Games).
    func giveOwnBottle(_ id: String) async {
        guard let game = game(id), let bottle = game.bottle, !bottleIsBusy(bottle) else { return }
        let name = BottleCopy.name(for: game.title, from: bottle, in: roots.bottles)
        copyingBottle = id
        defer { copyingBottle = nil }
        do {
            try await BottleCopy.copy(bottleURL(bottle), to: bottleURL(name))
        } catch {
            log.post(.error, "Can't copy the bottle \(bottle): \(error.localizedDescription)", source: "Settings")
            notices[id] = .didntCopy(error.localizedDescription)
            return
        }
        log.post(.info, "Copied the bottle \(bottle) to \(name) for \(game.title)", source: "Settings")
        await refresh()
        let newID = id.replacingOccurrences(of: "bottle:\(bottle):", with: "bottle:\(name):")
        guard library.games.contains(where: { $0.id == newID }) else {
            log.post(.error, "\(game.title) wasn't found in the copied bottle \(name)", source: "Settings")
            return
        }
        library.moveGame(from: id, to: newID)
        selectedGameID = newID
        settingsGeneration += 1
    }

    /// "CrossOver, bottle Steam", or the Wine build the person chose.
    func runnerLabel(_ game: Game) -> String {
        guard let path = game.options.runner, game.runner == .crossOver, game.steamID == nil else { return game.runnerLabel }
        return runners.first { $0.path == path }?.name ?? String(localized: "A runner that isn't installed anymore")
    }

    /// Changes a game's own options (Settings tab): kept in the library, used at the next launch.
    func setOptions(_ id: String, _ change: (inout GameOptions) -> Void) {
        guard let index = library.games.firstIndex(where: { $0.id == id }) else { return }
        change(&library.games[index].options)
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
