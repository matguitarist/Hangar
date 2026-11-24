import SwiftUI

/// Above the library while View › Fetch All Details runs: "Fetching game details… 12 of 40", then the result.
struct DetailsBanner: View {
    @Environment(AppModel.self) private var model
    let run: DetailsRun

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: run.finished ? "checkmark.circle" : "text.magnifyingglass")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Spacer()
                if run.finished {
                    Button("Dismiss") { model.detailsRun = nil }
                } else {
                    Button("Stop") { model.stopFetchingDetails() }
                        .help(String(localized: "Stop after the current game; what was found stays"))
                }
            }
            if run.finished {
                Text(note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView(value: Double(run.done), total: Double(max(run.total, 1)))
                    .accessibilityLabel(Text("\(run.done) of \(run.total) games"))
            }
        }
        .padding(Space.lg)
        .cardBackground()
    }

    private var title: String {
        if !run.finished { return String(localized: "Fetching game details… \(run.done) of \(run.total)") }
        return run.stopped ? String(localized: "Stopped after \(run.done) of \(run.total) games")
            : String(localized: "Found details for \(run.found) of \(run.total) games")
    }

    private var note: String {
        if model.theGamesDBKey.isEmpty {
            return String(localized: "Games that aren't on Steam need a TheGamesDB key, in Settings › Library.")
        }
        return String(localized: "A game with no details may have another name on TheGamesDB. Open its page to see what was found.")
    }
}
