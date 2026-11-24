import HangarKit
import SwiftUI

/// A runner update, and the games that last worked on the version before it.
struct RunnerUpdateNotice: Identifiable, Equatable {
    var update: RunnerUpdate
    var snapshots: [SettingsSnapshot]
    /// Bottles whose settings the update changed (S-040).
    var drifts: [BottleDrift] = []
    /// Bottles put back from this banner, which can be undone.
    var putBack: Set<String> = []
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
            let drifts = runners.first { $0.path == update.path }?.kind == .crossOver ? bottleDrifts() : []
            log.post(.info, "\(update.name) updated from \(update.old) to \(update.new); \(snapshots.count) games last worked on \(update.old); \(drifts.count) bottles changed", source: "Runners")
            for drift in drifts {
                log.post(.warning, "\(update.name) changed the settings of the bottle \(drift.bottle): " + drift.changes.map { "\($0.name) \($0.old) → \($0.new)" }.joined(separator: ", "), source: "Runners")
            }
            runnerUpdates.removeAll { $0.id == update.id }
            if !snapshots.isEmpty || !drifts.isEmpty { runnerUpdates.append(RunnerUpdateNotice(update: update, snapshots: snapshots, drifts: drifts)) }
        }
    }
}

extension AppModel {
    /// Each CrossOver bottle with games in it, compared with its newest snapshot (S-040).
    func bottleDrifts() -> [BottleDrift] {
        let map = Dictionary(grouping: library.games.filter { $0.runner == .crossOver && $0.bottle != nil }, by: { $0.bottle! }).mapValues { $0.map(\.id) }
        return RunnerVersions.drifts(bottles: map, bottleURL: bottleURL, store: snapshots)
    }

    /// Put Back My Settings: the snapshot's settings, after a snapshot of the bottle as the update left it.
    func putBack(_ drift: BottleDrift, in noticeID: String) {
        guard !bottleIsBusy(drift.bottle), let index = runnerUpdates.firstIndex(where: { $0.id == noticeID }) else { return }
        changeBottleSettings(drift.snapshot.gameID, to: drift.was)
        runnerUpdates[index].putBack.insert(drift.bottle)
        log.post(.info, "Put back the settings of the bottle \(drift.bottle)", source: "Runners")
    }

    /// Undo: the settings as the update left them.
    func undoPutBack(_ drift: BottleDrift, in noticeID: String) {
        guard !bottleIsBusy(drift.bottle), let index = runnerUpdates.firstIndex(where: { $0.id == noticeID }) else { return }
        changeBottleSettings(drift.snapshot.gameID, to: drift.now)
        runnerUpdates[index].putBack.remove(drift.bottle)
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
            ForEach(notice.drifts) { drift in
                DriftRow(notice: notice, drift: drift)
            }
            if !notice.snapshots.isEmpty {
                Text("These games last worked on \(notice.update.oldLabel). If one stops working, go back to its snapshot from then.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

/// "CrossOver changed the settings of the bottle Steam: Graphics D3DMetal → Auto", and the button that puts them back.
private struct DriftRow: View {
    @Environment(AppModel.self) private var model
    let notice: RunnerUpdateNotice
    let drift: BottleDrift

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                if notice.putBack.contains(drift.bottle) {
                    Text("Your settings for the bottle \(drift.bottle) are back.")
                } else {
                    Text("\(notice.update.name) changed the settings of the bottle \(drift.bottle):")
                    ForEach(drift.changes, id: \.name) { change in
                        Text("\(change.name): \(change.old) → \(change.new)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if notice.putBack.contains(drift.bottle) {
                Button("Undo") { model.undoPutBack(drift, in: notice.id) }
            } else {
                Button("Put Back My Settings") { model.putBack(drift, in: notice.id) }
                    .disabled(model.bottleIsBusy(drift.bottle))
                    .help(model.bottleIsBusy(drift.bottle) ? String(localized: "Quit the games in this bottle first")
                                                           : String(localized: "Go back to the settings from \(drift.snapshot.date.formatted(date: .abbreviated, time: .shortened))"))
            }
        }
    }
}
