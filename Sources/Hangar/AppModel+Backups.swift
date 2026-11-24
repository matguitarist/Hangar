import AppKit
import Foundation
import HangarKit

/// Save backups (S-022) and restoring them (S-023).
extension AppModel {
    var saveBackups: SaveBackupStore { SaveBackupStore(root: Store.saveBackupsFolder(iCloud: backupsInICloud)) }

    func backupList(_ id: String) -> [SaveBackup] {
        _ = backupGeneration
        return saveBackups.list(id)
    }

    /// Copies a game's saves, unless they're unchanged since the last copy. Never stops a launch:
    /// a copy that fails is logged.
    @discardableResult
    func backUpSaves(_ id: String, reason: SaveBackup.Reason) async -> SaveBackup? {
        await loadSaveLocations(id, force: true)
        guard let game = game(id) else { return nil }
        let saves = knownSaveLocations(id).filter { $0.kind == .saves }.flatMap(\.found)
        guard !saves.isEmpty else { return nil }
        let store = saveBackups
        let result = await Task.detached { () -> Result<SaveBackup?, Error> in
            Result { try store.backUp(id, saves: saves, reason: reason) }
        }.value
        switch result {
        case let .success(backup):
            if let backup {
                backupGeneration += 1
                healthIssues.removeAll { $0 == .neverBackedUp(gameID: id) }
                log.post(.info, "Backed up the saves of \(game.title): \(backup.files) files", source: "Saves")
            }
            return backup
        case let .failure(error):
            log.post(.error, "Can't back up the saves of \(game.title): \(error.localizedDescription)", source: "Saves")
            return nil
        }
    }

    /// Puts a backup's saves back, after backing up the current ones. Not while the game runs.
    func restoreBackup(_ backup: SaveBackup, gameID: String) async {
        guard running[gameID] == nil, let game = game(gameID) else { return }
        await backUpSaves(gameID, reason: .beforeRestore)
        let store = saveBackups
        let result = await Task.detached { Result { try store.restore(backup, gameID: gameID) } }.value
        switch result {
        case .success:
            log.post(.info, "Restored the saves of \(game.title) from \(backup.date.formatted())", source: "Saves")
        case let .failure(error):
            log.post(.error, "Can't restore the saves of \(game.title): \(error.localizedDescription)", source: "Saves")
        }
        backupGeneration += 1
        await loadSaveLocations(gameID, force: true)
    }

    /// Show in Finder for a backup's folder. A test run records it instead.
    func showBackup(_ backup: SaveBackup, gameID: String) {
        let folder = saveBackups.location(of: backup, gameID: gameID)
        if Store.isOverridden { openedURLs.append(folder); return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func moveBackups(from old: SaveBackupStore) {
        do {
            try old.move(to: saveBackups)
            log.post(.info, "Moved the save backups to \(saveBackups.root.path)", source: "Saves")
        } catch {
            log.post(.error, "Can't move the save backups: \(error.localizedDescription)", source: "Saves")
        }
        backupGeneration += 1
    }
}
