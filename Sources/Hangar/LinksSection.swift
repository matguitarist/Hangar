import HangarKit
import SwiftUI

/// "On the Web": the game's pages on the wikis, CodeWeavers, ProtonDB and its store.
struct LinksSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let page: String? = if case let .some(.some(compatibility)) = model.compatibility[game.id] { compatibility.page } else { nil }
        Section {
            ForEach(GameLinks.links(title: game.title, steamID: game.steamID, wikiPage: page)) { link in
                Button {
                    model.open(link.url)
                } label: {
                    LabeledContent(link.site.name) {
                        Image(systemName: link.isSearch ? "magnifyingglass" : "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(link.isSearch ? String(localized: "Search \(link.site.name) for \(game.title)") : String(localized: "Open the page of \(game.title) on \(link.site.name)"))
                .accessibilityHint(link.isSearch ? Text("Searches by title") : Text("Opens the game's page"))
            }
        } header: {
            Text("On the Web")
        }
    }
}
