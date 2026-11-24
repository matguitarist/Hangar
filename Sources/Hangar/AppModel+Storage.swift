import AppKit
import HangarKit

/// The Storage page (S-039): sizes on disk, and freeing space.
extension AppModel {
    func measureStorage() async {
        guard !measuringStorage else { return }
        measuringStorage = true
        defer { measuringStorage = false }
        let used = Set(library.games.filter { $0.options.runner != nil }
            .map { LaunchPlanner.prefix(for: $0, roots: roots).standardizedFileURL.path })
        let input = StorageScanner.Input(games: library.games, bottles: roots.bottles, bottleNames: bottles, prefixes: roots.prefixes,
                                         usedPrefixes: used, snapshots: Store.snapshotsFolder, saveBackups: saveBackups.root)
        storageItems = await StorageScanner.measure(input)
    }

    /// An unused prefix to the Trash (a test run deletes it: /tmp has no Trash).
    func trashPrefix(_ item: StorageItem) async {
        guard item.kind == .prefixes, item.unused else { return }
        let url = URL(fileURLWithPath: item.path)
        do {
            if Store.isOverridden { try FileManager.default.removeItem(at: url) } else { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            log.post(.info, "Moved the unused prefix \(item.name) to the Trash", source: "Storage")
        } catch {
            log.post(.error, "Can't move \(item.name) to the Trash: \(error.localizedDescription)", source: "Storage")
        }
        await measureStorage()
    }

    func deleteOldSnapshots() async {
        let ids = library.games.map(\.id) + library.removed.map(\.id)
        let store = snapshots
        let removed = await Task.detached { store.deleteOld(gameIDs: ids) }.value
        snapshotGeneration += 1
        log.post(.info, "Deleted \(removed) old snapshots", source: "Storage")
        await measureStorage()
    }

    func deleteOldBackups() async {
        let ids = library.games.map(\.id) + library.removed.map(\.id)
        let store = saveBackups
        let removed = await Task.detached { store.deleteOld(gameIDs: ids) }.value
        backupGeneration += 1
        log.post(.info, "Deleted \(removed) old save backups", source: "Storage")
        await measureStorage()
    }

    func showStorageItem(_ item: StorageItem) {
        let url = URL(fileURLWithPath: item.path)
        if Store.isOverridden { openedURLs.append(url); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension StorageItem.Kind {
    var title: String {
        switch self {
        case .games: String(localized: "Games")
        case .bottles: String(localized: "Bottles")
        case .prefixes: String(localized: "Prefixes")
        case .snapshots: String(localized: "Snapshots")
        case .saveBackups: String(localized: "Save Backups")
        }
    }
}
