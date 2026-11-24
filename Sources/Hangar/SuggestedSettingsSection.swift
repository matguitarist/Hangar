import HangarKit
import SwiftUI

/// "Suggested Settings" on a Windows game's page (S-034): what the wikis recommend, why, and Apply.
struct SuggestedSettingsSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let list = model.suggestions(for: game)
        if case .applied = model.suggestionState[game.id] {
            Section {
                HStack(spacing: Space.sm) {
                    Label("Applied the suggested settings.", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Undo") { model.undoSuggestions(game.id) }
                        .help(String(localized: "Go back to the settings from before"))
                }
            } header: {
                Text("Suggested Settings")
            }
        } else if model.suggestionState[game.id] == nil, !list.isEmpty {
            let busy = game.bottle.map(model.bottleIsBusy) ?? false
            Section {
                ForEach(list) { suggestion in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        LabeledContent(title(suggestion.change)) { Text(value(suggestion.change)) }
                        Text(reason(suggestion))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: Space.sm) {
                    Button("Apply Suggestions") { model.applySuggestions(game.id) }
                        .disabled(busy)
                        .help(busy ? String(localized: "Quit the games in this bottle first")
                              : String(localized: "A snapshot is saved first, so you can go back"))
                    Button("Not Now") { model.suggestionState[game.id] = .dismissed }
                }
                if busy {
                    Text("Quit the games in this bottle first").font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Suggested Settings")
            } footer: {
                Text("From the wikis, not tested on this Mac.").foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ change: SettingsSuggestion.Change) -> String {
        switch change {
        case .graphics: String(localized: "Graphics")
        case .msync: "MSync"
        case .avx: String(localized: "AVX for Rosetta")
        case .highResolution: String(localized: "High Resolution Mode")
        }
    }

    private func value(_ change: SettingsSuggestion.Change) -> String {
        if case let .graphics(backend) = change { return backend.title }
        return String(localized: "On")
    }

    private func reason(_ suggestion: SettingsSuggestion) -> String {
        switch suggestion.reason {
        case let .wikiNote(sentence):
            return String(localized: "AppleGamingWiki: “\(sentence)”")
        case let .directX(version):
            let backend = if case let .graphics(b) = suggestion.change { b.title } else { "" }
            return String(localized: "PCGamingWiki lists Direct3D \(version); \(backend) usually runs that best.")
        }
    }
}
