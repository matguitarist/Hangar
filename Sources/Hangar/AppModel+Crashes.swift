import AppKit
import Foundation
import HangarKit

/// What Hangar can do about a crash, as one button on the notice.
enum CrashFix: Equatable {
    /// Switch the bottle's graphics (a snapshot is taken first).
    case useGraphics(GraphicsBackend)
    /// Open CrossOver, to install a runtime in the bottle.
    case openCrossOver
}

/// Why a Windows game crashed (S-024), from its Wine log.
extension AppModel {
    func wineLogURL(_ id: String) -> URL {
        Store.wineLogsFolder.appending(path: id.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined() + ".log")
    }

    /// Reads the game's Wine log and shows the reason on its page.
    func readCrash(_ id: String) {
        let text = (try? String(contentsOf: wineLogURL(id), encoding: .utf8))
            ?? (try? String(contentsOf: wineLogURL(id), encoding: .isoLatin1)) ?? ""
        let reason = CrashReadout.reason(in: text)
        notices[id] = .crashed(reason)
        if let reason {
            log.post(.warning, "\(game(id)?.title ?? id): \(reason.title) (\(reason.line))", source: "Launch")
        }
    }

    /// The button the notice offers, when Hangar can help.
    func crashFix(_ game: Game, _ reason: CrashReason) -> CrashFix? {
        switch reason.kind {
        case let .needsGraphics(backend):
            guard game.runner == .crossOver, game.options.runner == nil, let settings = bottleSettings(for: game), settings.graphics != backend else { return nil }
            return .useGraphics(backend)
        case .missingRuntime:
            return game.runner == .crossOver && game.options.runner == nil && roots.crossOverApp != nil ? .openCrossOver : nil
        case .missingFile, .outOfMemory:
            return nil
        }
    }

    func apply(_ fix: CrashFix, to id: String) {
        guard let game = game(id) else { return }
        switch fix {
        case let .useGraphics(backend):
            guard var settings = bottleSettings(for: game) else { return }
            settings.graphics = backend
            changeBottleSettings(id, to: settings)
            notices[id] = nil
        case .openCrossOver:
            guard let app = roots.crossOverApp else { return }
            if Store.isOverridden { openedURLs.append(app); return }
            NSWorkspace.shared.open(app)
        }
    }
}
