import AppKit
import HangarKit

/// Library health (S-042): what needs the person, and the fix for each.
extension AppModel {
    /// Checks the library again. `loadSaves` looks up where every game saves first (PCGamingWiki, cached for a month);
    /// without it, only the saves already looked up count.
    func checkHealth(loadSaves: Bool) async {
        if loadSaves {
            checkingHealth = true
            for game in library.games { await loadSaveLocations(game.id) }
            checkingHealth = false
        }
        let games = library.games
        let store = saveBackups
        let ids = games.map(\.id)
        let backedUp = await Task.detached { Set(ids.filter { !store.list($0).isEmpty }) }.value
        let withSaves = Set(games.filter { game in knownSaveLocations(game.id).contains { $0.kind == .saves && $0.exists } }.map(\.id))
        let facts = HealthFacts(games: games, missingFiles: Set(games.filter(filesMissing).map(\.id)),
                                unreadableBottles: notes.compactMap { if case let .bottleUnreadable(name) = $0 { name } else { nil } },
                                signedOutBottles: signedOutBottles, gamesWithSaves: withSaves, gamesWithBackups: backedUp)
        healthIssues = LibraryHealth.issues(facts)
    }

    func fixHealth(_ issue: HealthIssue) async {
        switch issue {
        case let .filesMoved(id):
            GamePanels.locate(self, id)
        case .bottleUnreadable:
            guard let app = roots.crossOverApp else { return }
            if Store.isOverridden { openedURLs.append(app) } else { NSWorkspace.shared.open(app) }
        case let .signedOut(bottle):
            openSteam(bottle: bottle)
        case let .neverBackedUp(id):
            _ = await backUpSaves(id, reason: .byHand)
        }
        await checkHealth(loadSaves: false)
    }
}

extension HealthIssue.Kind {
    var title: String {
        switch self {
        case .filesMoved: String(localized: "Files moved")
        case .bottleUnreadable: String(localized: "Bottles Hangar can't read")
        case .signedOut: String(localized: "Signed out of Steam")
        case .neverBackedUp: String(localized: "Never backed up")
        }
    }

    var symbol: String {
        switch self {
        case .filesMoved: "questionmark.folder"
        case .bottleUnreadable: "shippingbox"
        case .signedOut: "person.crop.circle.badge.exclamationmark"
        case .neverBackedUp: "externaldrive.badge.exclamationmark"
        }
    }

    var fix: String {
        switch self {
        case .filesMoved: String(localized: "Locate…")
        case .bottleUnreadable: String(localized: "Open in CrossOver")
        case .signedOut: String(localized: "Open Steam")
        case .neverBackedUp: String(localized: "Back Up Now")
        }
    }
}
