import HangarKit
import SwiftUI

/// A runner update, and the games that last worked on the version before it.
struct RunnerUpdateNotice: Identifiable, Equatable {
    var update: RunnerUpdate
    var snapshots: [SettingsSnapshot]
    var id: String { update.id }
}

extension AppModel {
    /// Compares the runners with the versions seen last, and remembers the new ones.
    func checkRunnerUpdates() {
        let url = Store.runnerVersionsURL
        let updates = RunnerVersions.changes(previous: RunnerVersions.load(url), current: runners)
        do {
            try RunnerVersions.save(runners, to: url)
        } catch {
            log.post(.error, "Can't save the runner versions: \(error.localizedDescription)", source: "Runners")
        }
        for update in updates {
            let snapshots = RunnerVersions.lastWorked(on: update, gameIDs: library.games.map(\.id), store: snapshots)
            log.post(.info, "\(update.name) updated from \(update.old) to \(update.new); \(snapshots.count) games last worked on \(update.old)", source: "Runners")
            runnerUpdates.removeAll { $0.id == update.id }
            if !snapshots.isEmpty { runnerUpdates.append(RunnerUpdateNotice(update: update, snapshots: snapshots)) }
        }
    }
}

/// Above the library grid: "CrossOver updated from 26.3 to 26.4", with the games to watch.
struct RunnerUpdateBanner: View {
    @Environment(AppModel.self) private var model
    let notice: RunnerUpdateNotice

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("\(notice.update.name) updated from \(notice.update.old) to \(notice.update.new)")
                    .font(.headline)
                Spacer()
                Button("Dismiss") { model.runnerUpdates.removeAll { $0.id == notice.id } }
            }
            Text("These games last worked on \(notice.update.oldLabel). If one stops working, go back to its snapshot from then.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notice.snapshots) { snapshot in
                HStack(spacing: Space.sm) {
                    Text(model.game(snapshot.gameID)?.title ?? snapshot.gameID)
                    Text(snapshot.title)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Snapshots…") {
                        model.selectedGameID = snapshot.gameID
                        model.showsSnapshots = snapshot.gameID
                    }
                    .help(String(localized: "Go back to settings that worked"))
                }
            }
        }
        .padding(Space.lg)
        .cardBackground()
    }
}
