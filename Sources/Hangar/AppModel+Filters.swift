import HangarKit

/// Smart filters (S-043).
extension AppModel {
    /// Windows games a store or AppleGamingWiki says have a Mac version, from what's loaded.
    var macVersionIDs: Set<String> {
        Set(library.games.filter { game in
            guard game.isWindows else { return false }
            let stores = macVersions(game)
            if stores.steam || stores.appStore != nil { return true }
            if case let .some(.some(compatibility)) = compatibility[game.id] { return compatibility.entries.contains { $0.method == .native } }
            return false
        }.map(\.id))
    }

    /// "Has a Mac Version" needs each Windows game's details and verdicts (both cached on disk).
    func loadMacVersions() async {
        for game in library.games where game.isWindows {
            _ = await loadDetails(game.id)
            await loadCompatibility(game.id)
        }
    }
}

extension GameFilter {
    var title: String {
        switch self {
        case .neverPlayed: String(localized: "Never Played")
        case .notPlayedRecently: String(localized: "Not Played in 6 Months")
        case .windows: String(localized: "Windows Games")
        case .mac: String(localized: "Mac Games")
        case .hasMacVersion: String(localized: "Has a Mac Version")
        }
    }
}
