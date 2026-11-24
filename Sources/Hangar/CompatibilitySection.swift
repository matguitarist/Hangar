import HangarKit
import SwiftUI

/// "Runs on a Mac": AppleGamingWiki's verdict for each method, on the game page.
struct CompatibilitySection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var showsLoading = false

    var body: some View {
        Section {
            macVersion
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
            if !hasNativeVerdict { await model.loadAppStore(game.id) }
        }
    }

    private var hasNativeVerdict: Bool {
        if case let .some(.some(compatibility)) = model.compatibility[game.id] {
            return compatibility.entries.contains { $0.method == .native }
        }
        return false
    }

    /// S-033: when the wiki gives no native verdict, the stores still say whether a Mac version exists.
    @ViewBuilder
    private var macVersion: some View {
        let stores = model.macVersions(game)
        if model.compatibility[game.id] != nil, !hasNativeVerdict, stores.steam || stores.appStore != nil {
            VStack(alignment: .leading, spacing: Space.xs) {
                LabeledContent(Compatibility.Method.native.title) {
                    Label("Mac version", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                        .help(String(localized: "A store sells a version for macOS. How well it runs isn't rated."))
                }
                if stores.steam {
                    Text("Steam sells a Mac version of this game.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let app = stores.appStore {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text("On the Mac App Store.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open in the App Store") { model.open(app.url) }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
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
