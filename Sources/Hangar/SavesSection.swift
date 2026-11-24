import HangarKit
import SwiftUI

/// "Saves": where a game keeps its saves and settings, from PCGamingWiki, on the game page.
struct SavesSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var showsLoading = false

    var body: some View {
        Section {
            switch model.saveLocations[game.id] {
            case .none:
                if showsLoading {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Checking PCGamingWiki…").foregroundStyle(.secondary)
                    }
                }
            case .some(.none):
                Text("PCGamingWiki has no page for this game yet.")
                    .foregroundStyle(.secondary)
            case let .some(.some(locations)):
                if locations.isEmpty {
                    Text("PCGamingWiki doesn't say where this game saves.").foregroundStyle(.secondary)
                }
                ForEach(locations) { location in
                    row(location)
                }
                if let last = model.backupList(game.id).first {
                    LabeledContent {
                        Button("Backups…") { model.showsBackups = game.id }
                            .fixedSize()
                            .help(String(localized: "See the save backups and restore one"))
                    } label: {
                        Text("Last backup: \(last.date.formatted(.relative(presentation: .named)))")
                            .help(last.date.formatted(date: .complete, time: .shortened))
                    }
                }
            }
        } header: {
            Text("Saves")
        } footer: {
            if let page = model.saveDataPages[game.id] {
                Link(String(localized: "From PCGamingWiki"), destination: page)
                    .font(.footnote)
            }
        }
        .task(id: game.id) {
            showsLoading = false
            let reveal = Task { try? await Task.sleep(for: .milliseconds(500)); showsLoading = true }
            await model.loadSaveLocations(game.id)
            reveal.cancel()
        }
    }

    private func row(_ location: SaveLocation) -> some View {
        LabeledContent {
            Button("Show in Finder") { model.showSaveLocation(location) }
                .fixedSize()
        } label: {
            Text(location.kind == .saves ? String(localized: "Saves") : String(localized: "Settings"))
            Text(location.exists ? location.folder.path.abbreviatingHome : String(localized: "Not on this Mac yet"))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(location.path)
        }
    }
}

extension String {
    /// "/Users/me/Library/…" → "~/Library/…".
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
