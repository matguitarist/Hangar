import Foundation
import HangarKit

/// Snapshots of a game's settings and bottle files: taken before changes and launches, restored on request.
extension AppModel {
    /// "CrossOver 26.3", "Wine Stable 10.0", or nil for a Mac game.
    func runnerVersion(_ game: Game) -> String? {
        let runner: InstalledRunner?
        if let path = game.options.runner, game.runner == .crossOver, game.steamID == nil {
            runner = runners.first { $0.path == path }
        } else if game.runner == .crossOver {
            runner = runners.first { $0.kind == .crossOver }
        } else {
            runner = nil
        }
        return runner.map { r in r.version.map { "\(r.name) \($0)" } ?? r.name }
    }

    /// Saves the game's settings and bottle files. Returns nil (and logs why) when it can't.
    @discardableResult
    func takeSnapshot(_ id: String, reason: SettingsSnapshot.Reason, extraFiles: [String] = [], detail: String? = nil) -> SettingsSnapshot? {
        guard let game = game(id) else { return nil }
        let bottle = game.runner == .crossOver ? game.bottle.map(bottleURL) : nil
        do {
            let snapshot = try snapshots.take(game, bottle: bottle, extraFiles: extraFiles, reason: reason, detail: detail, runner: runnerVersion(game))
            snapshotGeneration += 1
            return snapshot
        } catch {
            log.post(.error, "Can't save a snapshot of \(game.title): \(error.localizedDescription)", source: "Snapshots")
            return nil
        }
    }

    func snapshotList(_ id: String) -> [SettingsSnapshot] {
        _ = snapshotGeneration
        return snapshots.list(id)
    }

    /// "It Worked" after a game ran: labels the snapshot taken when it started.
    func markWorked(_ id: String) {
        notices[id] = nil
        guard let snapshot = launchSnapshots[id] ?? snapshots.list(id).first else { return }
        do {
            try snapshots.markWorked(snapshot)
            snapshotGeneration += 1
            log.post(.info, "\(game(id)?.title ?? id) worked with the snapshot of \(snapshot.date.formatted())", source: "Snapshots")
        } catch {
            log.post(.error, "Can't label the snapshot: \(error.localizedDescription)", source: "Snapshots")
        }
    }

    /// Puts a game's settings and bottle files back. The current ones are saved first, so this can be undone.
    func restore(_ snapshot: SettingsSnapshot) {
        guard let game = game(snapshot.gameID) else { return }
        if let bottle = game.bottle, bottleIsBusy(bottle) { return }
        takeSnapshot(game.id, reason: .restore, extraFiles: snapshot.files.map(\.path))
        let bottle = game.runner == .crossOver ? (snapshot.bottle ?? game.bottle).map(bottleURL) : nil
        do {
            let options = try snapshots.restore(snapshot, bottle: bottle)
            setOptions(game.id) { $0 = options }
            log.post(.info, "Restored \(game.title) to the snapshot of \(snapshot.date.formatted())", source: "Snapshots")
        } catch {
            log.post(.error, "Can't restore \(game.title): \(error.localizedDescription)", source: "Snapshots")
        }
        settingsGeneration += 1
        snapshotGeneration += 1
    }
}

extension SettingsSnapshot {
    /// "Worked on 12 Nov 2026" or "24 Nov 2026 at 14:05".
    var title: String {
        if let worked {
            return String(localized: "Worked on \(worked.formatted(date: .abbreviated, time: .omitted))")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var reasonText: String {
        switch reason {
        case .settings: String(localized: "Before changing settings")
        case .launch: String(localized: "Before playing")
        case .recipe: String(localized: "Before applying \(detail ?? "a recipe")")
        case .restore: String(localized: "Before restoring an earlier snapshot")
        }
    }
}
