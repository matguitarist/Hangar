import HangarKit
import SwiftUI

/// "About": what a game is, from the Steam store or TheGamesDB (S-031). Shows only when there's something to say.
struct AboutSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var expanded = false

    var body: some View {
        Group {
            if case let .some(.some(details)) = model.details[game.id] {
                Section {
                    if !details.summary.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(details.summary)
                                .lineLimit(expanded ? nil : 4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if details.summary.count > 220 || details.summary.contains("\n") {
                                Button(expanded ? String(localized: "Less") : String(localized: "More")) { expanded.toggle() }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                    row("Developer", details.developers)
                    row("Publisher", details.publishers)
                    if let released = released(details) {
                        LabeledContent("Released", value: released)
                    }
                    row("Genres", details.genres)
                } header: {
                    Text("About")
                } footer: {
                    if let url = details.url {
                        Link(details.source == .steam ? String(localized: "From the Steam store") : String(localized: "From TheGamesDB"), destination: url)
                            .font(.footnote)
                    }
                }
            }
        }
        .onChange(of: game.id) { expanded = false }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ values: [String]) -> some View {
        if !values.isEmpty {
            LabeledContent(title) {
                Text(values.joined(separator: ", "))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private func released(_ details: GameDetails) -> String? {
        details.releaseDate.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)) }
            ?? details.releaseText
    }
}
