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
                log.post(.info, "Backed up the saves of \(game.title): \(backup.files) files", source: "Saves")
            }
            return backup
        case let .failure(error):
            log.post(.error, "Can't back up the saves of \(game.title): \(error.localizedDescription)", source: "Saves")
            return nil
        }
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
