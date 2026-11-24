import AppKit
import HangarKit

/// What couch mode can be asked to do, by the keyboard or a controller (S-028, S-029).
enum CouchInput: Equatable {
    case move(CouchDirection)
    /// Return or A: play the selected game, or ask to stop it when it runs.
    case play
    /// Escape or B: close the details, else leave couch mode.
    case back
    /// Space or Y: the selected game's details.
    case details
    /// The controller's menu button: open couch mode from anywhere in Hangar.
    case menu
}

extension AppModel {
    /// View › Couch Mode: full screen, the selection where the library's was.
    func enterCouchMode() {
        guard !couchMode else { return }
        couch = CouchNavigator(rows: CouchNavigator.rows(for: library.games))
        if let id = selectedGameID { couch.select(id) }
        couchDetails = false
        couchMode = true
        // A test run never takes over the screen.
        if !Store.isOverridden, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Hangar" }),
           !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            couchMadeFullScreen = true
        }
        log.post(.info, "Couch mode on", source: "Couch")
    }

    func leaveCouchMode() {
        guard couchMode else { return }
        if let id = couch.selected { selectedGameID = id }
        couchMode = false
        couchDetails = false
        if couchMadeFullScreen, let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) {
            window.toggleFullScreen(nil)
        }
        couchMadeFullScreen = false
    }

    /// The rows again, after a game finished or a scan: the selection stays.
    func refreshCouchRows() {
        guard couchMode else { return }
        couch.update(rows: CouchNavigator.rows(for: library.games))
    }

    func couch(_ input: CouchInput) {
        if input == .menu {
            if couchMode { couchDetails = false } else { enterCouchMode() }
            return
        }
        guard couchMode else { return }
        switch input {
        case let .move(direction):
            guard !couchDetails else { return }
            couch.move(direction)
        case .play:
            guard let id = couch.selected else { return }
            if running[id] != nil { confirmingStop = id } else { play(id) }
        case .back:
            if couchDetails { couchDetails = false } else { leaveCouchMode() }
        case .details:
            guard let id = couch.selected else { return }
            couchDetails.toggle()
            if couchDetails { Task { await loadDetails(id) } }
        case .menu:
            break
        }
    }
}
