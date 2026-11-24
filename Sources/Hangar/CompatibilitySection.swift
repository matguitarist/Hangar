import HangarKit
import SwiftUI

/// "Runs on a Mac": AppleGamingWiki's verdict for each method, on the game page.
struct CompatibilitySection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var showsLoading = false

    var body: some View {
        Section {
            switch model.compatibility[game.id] {
            case .none:
                if showsLoading {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Checking AppleGamingWiki…").foregroundStyle(.secondary)
                    }
                }
            case .some(.none):
                Text("AppleGamingWiki has no page for this game yet.")
                    .foregroundStyle(.secondary)
                Link("Search AppleGamingWiki", destination: GameLinks.appleGamingWikiSearch(game.title))
            case let .some(.some(compatibility)):
                if compatibility.entries.isEmpty {
                    Text("AppleGamingWiki has no verdicts for this game yet.").foregroundStyle(.secondary)
                }
                ForEach(compatibility.entries, id: \.method) { entry in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        LabeledContent(entry.method.title) {
                            RatingTag(rating: entry.rating)
                        }
                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .help(entry.notes)
                        }
                    }
                }
            }
        } header: {
            Text("Runs on a Mac")
        } footer: {
            if case let .some(.some(compatibility)) = model.compatibility[game.id] {
                Link(String(localized: "From AppleGamingWiki"), destination: compatibility.url)
                    .font(.footnote)
            }
        }
        .task(id: game.id) {
            showsLoading = false
            let reveal = Task { try? await Task.sleep(for: .milliseconds(500)); showsLoading = true }
            await model.loadCompatibility(game.id)
            reveal.cancel()
        }
    }
}

/// A verdict as a word with a symbol, never color alone.
private struct RatingTag: View {
    let rating: Compatibility.Rating

    var body: some View {
        Label(rating.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch rating {
        case .perfect: "checkmark.circle.fill"
        case .playable: "checkmark.circle"
        case .runs: "exclamationmark.circle"
        case .unplayable: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch rating {
        case .perfect, .playable: .green
        case .runs: .orange
        case .unplayable: .red
        case .unknown: .secondary
        }
    }
}
