import AppKit
import Foundation
import HangarKit
import SwiftUI
import UniformTypeIdentifiers

/// What people do with games: play, stop, add, remove, collections, covers.
extension AppModel {
    // MARK: Play and stop

    /// Starts a game through its runner. Running and playtime then follow its own process.
    /// A Steam game in a signed-out bottle asks to sign in first, unless the person plays anyway (S-037).
    func play(_ id: String, anyway: Bool = false) {
        guard let game = game(id), running[id] == nil else { return }
        notices[id] = nil
        if !anyway, needsSteamSignIn(game), let bottle = game.bottle {
            notices[id] = .signInFirst(bottle)
            log.post(.warning, "\(game.title) waits: Steam in the bottle \(bottle) is signed out", source: "Launch")
            return
        }
        var plan: LaunchPlan
        let battery: BatteryProfile?
        do {
            (plan, battery) = try launchPlan(for: game)
        } catch {
            let reason = switch error {
            case .crossOverMissing: String(localized: "CrossOver isn't installed.")
            case .runnerMissing: String(localized: "Its runner isn't installed anymore.")
            case .filesMissing: String(localized: "The game's files aren't at this location anymore.")
            case .noBottle: String(localized: "It has no bottle.")
            case .heroicMissing: String(localized: "Heroic isn't installed.")
            }
            notices[id] = .didntStart(reason)
            log.post(.error, "\(game.title) didn't start: \(reason)", source: "Launch")
            return
        }
        if game.isWindows {
            // Wine's messages go to the game's own log, read if it quits within a minute (S-024).
            let wineLog = wineLogURL(id)
            try? FileManager.default.createDirectory(at: wineLog.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: wineLog)
            plan = plan.loggingWine(to: wineLog)
        }
        if let snapshot = takeSnapshot(id, reason: .launch) { launchSnapshots[id] = snapshot }
        running[id] = LaunchState(launched: Date(), slowStart: game.isWindows || game.source == .steam)
        if let battery { applyBatteryProfile(game, battery) }
        log.post(.info, "Starting \(game.title): \(plan.executable.lastPathComponent) \(plan.arguments.joined(separator: " "))", source: "Launch")
        if !plan.environment.isEmpty {
            log.post(.info, "With \(plan.environment.keys.sorted().joined(separator: ", "))", source: "Launch")
        }
        // The saves are copied before the game can change them (S-022).
        Task {
            await backUpSaves(id, reason: .launch)
            guard running[id] != nil else { return }
            launch(id, plan: plan)
        }
    }

    /// Starts the launch command, once the saves are backed up.
    private func launch(_ id: String, plan: LaunchPlan) {
        if plan.executable.path == "/usr/bin/open", plan.arguments.count == 1, let app = plan.arguments.first, app.hasSuffix(".app") {
            // A Mac app: open it through Launch Services, which gives its process id at once.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            configuration.environment = plan.environment
            configuration.arguments = plan.appArguments
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app), configuration: configuration) { app, error in
                let pid = app?.processIdentifier
                let message = error?.localizedDescription
                Task { @MainActor in self.launched(id, pid: pid, error: message) }
            }
        } else {
            let process = Process()
            process.executableURL = plan.executable
            process.arguments = plan.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(plan.environment) { $1 }
            if let folder = plan.workingDirectory { process.currentDirectoryURL = folder }
            if let prefix = plan.environment["WINEPREFIX"] {
                try? FileManager.default.createDirectory(atPath: prefix, withIntermediateDirectories: true)
            }
            if let file = plan.outputFile, FileManager.default.createFile(atPath: file.path, contents: nil),
               let handle = try? FileHandle(forWritingTo: file) {
                process.standardOutput = handle
                process.standardError = handle
            } else {
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
            }
            do { try process.run() } catch { launched(id, pid: nil, error: error.localizedDescription) }
        }
        startMonitor()
    }

    private func launched(_ id: String, pid: pid_t?, error: String?) {
        guard var state = running[id] else { return }
        log.post(.debug, "Launch answered for \(game(id)?.title ?? id): pid \(pid.map(String.init) ?? "none")", source: "Launch")
        if let error {
            running[id] = nil
            notices[id] = .didntStart(error)
            log.post(.error, "\(game(id)?.title ?? id) didn't start: \(error)", source: "Launch")
            return
        }
        guard let pid, pid > 0 else {
            // Launch Services had no app to give back: it opened and quit before it could.
            running[id] = nil
            notices[id] = .quitRightAway
            log.post(.warning, "\(game(id)?.title ?? id) quit right away", source: "Launch")
            return
        }
        if LaunchTracker.launched(&state, pid: pid, now: Date()) == .started {
            running[id] = state
            announceRunning(id)
        }
    }

    /// Stop asks first (unsaved progress may be lost); this is the confirmed action.
    func stop(_ id: String) {
        guard var state = running[id] else { return }
        state.stoppedByUser = true
        running[id] = state
        for pid in state.pids { kill(pid, SIGTERM) }
        log.post(.info, "Stopped \(game(id)?.title ?? id)", source: "Launch")
    }

    /// Watches launched games every second and a half until none is left.
    func startMonitor() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while let self, !self.running.isEmpty, !Task.isCancelled {
                let processes = await ProcessList.snapshot()
                self.update(with: processes)
                try? await Task.sleep(for: .milliseconds(1500))
            }
            self?.monitor = nil
        }
    }

    private func update(with processes: [RunningProcess]) {
        let now = Date()
        for (id, var state) in running {
            guard let game = game(id) else { running[id] = nil; continue }
            let event = LaunchTracker.step(&state, hints: game.processHints, processes: processes, now: now)
            switch event {
            case .started:
                running[id] = state
                announceRunning(id)
            case let .finished(played, quitRightAway):
                finish(id, played: played, quitRightAway: quitRightAway, at: now)
            case .didntStart:
                running[id] = nil
                notices[id] = .didntStart(String(localized: "Its window never opened."))
                log.post(.error, "\(game.title) didn't start in time", source: "Launch")
            case nil:
                if state != running[id] { running[id] = state }
            }
        }
    }

    private func finish(_ id: String, played: TimeInterval, quitRightAway: Bool, at now: Date) {
        let stoppedByUser = running[id]?.stoppedByUser == true
        running[id] = nil
        restoreDisplay(after: id)
        if notices[id] == .lowPowerModeOff { notices[id] = nil }
        guard let index = library.games.firstIndex(where: { $0.id == id }) else { return }
        library.games[index].playtime += played
        library.games[index].lastPlayed = now
        if played > 0 {
            library.games[index].sessions = PlayHistory.adding(PlaySession(start: now.addingTimeInterval(-played), length: played),
                                                               to: library.games[index].sessions)
        }
        refreshCouchRows()
        Task { await loadAchievements(id, force: true) }
        // From the sofa, Hangar comes back when the game quits (S-029).
        if couchMode, !Store.isOverridden { NSApp.activate() }
        let title = library.games[index].title
        if library.games[index].isWindows, played < CrashReadout.window, !stoppedByUser {
            // A Windows game that quit within a minute: its Wine log may say why (S-024).
            log.post(.warning, "\(title) quit after \(Int(played)) seconds", source: "Launch")
            readCrash(id)
        } else if quitRightAway {
            notices[id] = .quitRightAway
            log.post(.warning, "\(title) quit after \(Int(played)) seconds", source: "Launch")
        } else {
            log.post(.info, "\(title) quit after \(Int(played)) seconds", source: "Launch")
            // A real session: ask whether it worked, to label the snapshot taken at launch.
            if played >= 60 { notices[id] = .askWorked }
        }
    }

    private func announceRunning(_ id: String) {
        guard let title = game(id)?.title else { return }
        log.post(.info, "\(title) is running", source: "Launch")
        AccessibilityNotification.Announcement(String(localized: "\(title) is running")).post()
    }

    /// Opens Steam in a bottle, to sign in.
    func openSteam(bottle: String) {
        guard let plan = try? LaunchPlanner.openSteam(bottle: bottle, roots: roots) else { return }
        let process = Process()
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        try? process.run()
    }

    /// Open in Heroic: where a Heroic game's settings live (S-036). A test run records it instead.
    func openHeroic() {
        guard let app = roots.heroicApp else { return }
        if Store.isOverridden { openedURLs.append(app); return }
        NSWorkspace.shared.open(app)
    }

    // MARK: Adding and removing

    /// A dropped or chosen file: an .app joins at once, anything else asks for the bottle.
    func add(files: [URL]) {
        for url in files where url.pathExtension.lowercased() == "app" { addApp(url) }
        if let other = files.first(where: { $0.pathExtension.lowercased() != "app" }) { addRequest = AddRequest(file: other) }
    }

    func addApp(_ url: URL) {
        if let existing = library.games.first(where: { $0.path == url.path }) {
            reveal(existing.id)
            return
        }
        let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist")) as? [String: Any]
        let title = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let game = Game(id: "hand:\(url.path)", title: title, source: .addedByHand, runner: .native, path: url.path, processHints: [url.path + "/"])
        insert(game)
    }

    func addWindowsGame(_ url: URL, bottle: String) {
        if let existing = library.games.first(where: { $0.path == url.path }) {
            reveal(existing.id)
            return
        }
        let exe = url.lastPathComponent
        let game = Game(id: "hand:\(url.path)", title: url.deletingPathExtension().lastPathComponent, source: .addedByHand, runner: .crossOver,
                        path: url.path, exe: LaunchPlanner.windowsPath(for: url, bottle: roots.bottles.appending(path: bottle)),
                        bottle: bottle, processHints: ["\\" + exe, "/" + exe])
        insert(game)
    }

    private func insert(_ game: Game) {
        let added = library.add(game)
        log.post(.info, "Added \(added.title)", source: "Library")
        reveal(added.id)
        undoManager?.registerUndo(withTarget: self) { model in
            model.library.games.removeAll { $0.id == added.id }
        }
        undoManager?.setActionName(String(localized: "Add Game"))
    }

    /// Shows a game in All Games and selects it.
    func reveal(_ id: String) {
        if case .collection = sidebar {} else if sidebar != .allGames, !games(for: sidebar ?? .allGames).contains(where: { $0.id == id }) {
            sidebar = .allGames
        }
        selectedGameID = id
    }

    /// Remove from Library: the game's files stay on disk; Settings › Library can bring it back.
    func remove(_ id: String) {
        guard game(id) != nil else { return }
        library.remove(id: id)
        if selectedGameID == id { selectedGameID = nil }
        undoManager?.registerUndo(withTarget: self) { model in model.restore(id) }
        undoManager?.setActionName(String(localized: "Remove from Library"))
    }

    func restore(_ id: String) {
        library.restore(id: id)
        undoManager?.registerUndo(withTarget: self) { model in model.remove(id) }
    }

    /// Locate…: the game's files moved; point the game at the new place.
    func locate(_ id: String, at url: URL) {
        guard let index = library.games.firstIndex(where: { $0.id == id }) else { return }
        library.games[index].path = url.path
        if library.games[index].runner == .native { library.games[index].processHints = [url.path + "/"] }
    }

    // MARK: Collections

    /// File › New Collection: added to the sidebar with its name ready to type.
    func newCollection(with gameIDs: [String] = []) {
        let collection = GameCollection(name: String(localized: "New Collection"), gameIDs: gameIDs)
        library.collections.append(collection)
        sidebar = .collection(collection.id)
        renamingCollection = collection.id
        undoManager?.registerUndo(withTarget: self) { model in model.deleteCollection(collection.id) }
        undoManager?.setActionName(String(localized: "New Collection"))
    }

    func renameCollection(_ id: UUID, to name: String) {
        guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { library.collections[index].name = trimmed }
        renamingCollection = nil
    }

    func deleteCollection(_ id: UUID) {
        guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
        let collection = library.collections.remove(at: index)
        if sidebar == .collection(id) { sidebar = .allGames }
        undoManager?.registerUndo(withTarget: self) { model in
            model.library.collections.insert(collection, at: min(index, model.library.collections.count))
        }
        undoManager?.setActionName(String(localized: "Delete Collection"))
    }

    func addToCollection(_ gameIDs: [String], _ id: UUID) {
        guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
        let new = gameIDs.filter { !library.collections[index].gameIDs.contains($0) }
        guard !new.isEmpty else { return }
        library.collections[index].gameIDs += new
        undoManager?.registerUndo(withTarget: self) { model in model.removeFromCollection(new, id) }
        undoManager?.setActionName(String(localized: "Add to Collection"))
    }

    func removeFromCollection(_ gameIDs: [String], _ id: UUID) {
        guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
        library.collections[index].gameIDs.removeAll { gameIDs.contains($0) }
        undoManager?.registerUndo(withTarget: self) { model in model.addToCollection(gameIDs, id) }
        undoManager?.setActionName(String(localized: "Remove from Collection"))
    }

    // MARK: Covers

    /// Choose Cover…: the image is copied next to the library, so it stays if the original moves.
    func chooseCover(_ id: String, image: URL) {
        guard let index = library.games.firstIndex(where: { $0.id == id }) else { return }
        let target = Store.coversFolder.appending(path: "custom-\(UUID().uuidString).\(image.pathExtension.isEmpty ? "png" : image.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: Store.coversFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: image, to: target)
            library.games[index].customCover = target.path
        } catch {
            log.post(.error, "Can't use that image as a cover: \(error.localizedDescription)", source: "Library")
        }
        syncMenu()
    }

    func resetCover(_ id: String) {
        guard let index = library.games.firstIndex(where: { $0.id == id }) else { return }
        library.games[index].customCover = nil
        syncMenu()
    }

    // MARK: Finder and store

    func showInFinder(_ id: String) {
        guard let game = game(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.path)])
    }

    func openStorePage(_ id: String) {
        guard let url = game(id)?.storeURL else { return }
        NSWorkspace.shared.open(url)
    }
}
