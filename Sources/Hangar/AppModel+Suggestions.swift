import Foundation
import HangarKit

/// A game's suggested settings after Apply or Not Now (S-034).
enum SuggestionState: Equatable {
    case dismissed
    /// Applied; the snapshot from just before, for Undo.
    case applied(SettingsSnapshot)
}

/// Suggested settings (S-034): what the wikis recommend for a Windows game's bottle.
extension AppModel {
    /// What to change in the game's bottle, best first; empty when it isn't a CrossOver bottle or nothing applies.
    func suggestions(for game: Game) -> [SettingsSuggestion] {
        guard game.runner == .crossOver, game.options.runner == nil, let current = bottleSettings(for: game) else { return [] }
        let notes = (compatibility[game.id] ?? nil)?.entries.first { $0.method == .crossOver }?.notes
        return SettingsAdvice.suggestions(current: current, crossOverNotes: notes, api: gameAPI[game.id])
    }

    /// Apply Suggestions: one change to the bottle, after a snapshot.
    func applySuggestions(_ id: String) {
        guard let game = game(id), var settings = bottleSettings(for: game) else { return }
        let list = suggestions(for: game)
        guard !list.isEmpty else { return }
        for suggestion in list { settings = suggestion.applied(to: settings) }
        changeBottleSettings(id, to: settings)
        if let before = snapshotList(id).first { suggestionState[id] = .applied(before) }
        log.post(.info, "Applied the suggested settings for \(game.title): \(list.map(\.id).joined(separator: ", "))", source: "Settings")
    }

    func undoSuggestions(_ id: String) {
        if case let .applied(snapshot) = suggestionState[id] { restore(snapshot) }
        suggestionState[id] = .dismissed
    }
}
