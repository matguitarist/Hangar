import Foundation
import HangarKit

/// Steam achievements (S-041), read from Steam's files on this Mac.
extension AppModel {
    func achievements(_ id: String) -> AchievementSummary? {
        achievementCache[id] ?? nil
    }

    /// The Steam folder that keeps a game's stats: the Mac's, or the bottle's for a game in CrossOver.
    func steamRoot(for game: Game) -> URL? {
        guard game.steamID != nil else { return nil }
        if game.runner == .crossOver, let bottle = game.bottle { return CrossOverScanner.steamFolder(bottle: bottleURL(bottle)) }
        return game.runner == .native ? roots.steam : nil
    }

    /// Reads the game's stats once per session, off the main thread; again after it was played.
    func loadAchievements(_ id: String, force: Bool = false) async {
        guard force || achievementCache[id] == nil, let game = game(id), let appID = game.steamID, let root = steamRoot(for: game) else { return }
        let language = SteamAchievements.language(for: Locale.preferredLanguages.first)
        let summary = await Task.detached { SteamAchievements.read(steamRoot: root, appID: appID, language: language) }.value
        achievementCache[id] = .some(summary)
    }
}
