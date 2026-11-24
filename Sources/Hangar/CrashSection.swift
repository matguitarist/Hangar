import HangarKit
import LogKitUI
import SwiftUI

/// "Hollow Knight quit: Missing Visual C++ 2022 runtime", what to do, and the Wine log (S-024).
struct CrashSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let game: Game
    let reason: CrashReason?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(reason.map { String(localized: "\(game.title) quit: \($0.title)") } ?? String(localized: "\(game.title) quit"),
                      systemImage: "exclamationmark.triangle")
                Text(reason?.advice ?? String(localized: "Hangar didn't find why. The Wine log may tell."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Side by side when they fit, one above the other when they don't (French is longer).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) { buttons }
                VStack(alignment: .leading, spacing: Space.sm) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if let reason, let fix = model.crashFix(game, reason) {
            Button(fix.title) { model.apply(fix, to: game.id) }
                .help(fix.help)
                .fixedSize()
        }
        Button("Show Log") { openWindow(id: "wine-log", value: game.id) }
            .help(String(localized: "Open the Wine log of the last launch"))
            .fixedSize()    }
}

extension CrashFix {
    var title: String {
        switch self {
        case let .useGraphics(backend): String(localized: "Use \(backend.title)")
        case .openCrossOver: String(localized: "Open CrossOver")
        }
    }

    var help: String {
        switch self {
        case .useGraphics: String(localized: "Change the bottle's graphics; a snapshot is taken first")
        case .openCrossOver: String(localized: "Install the runtime from CrossOver's Install Software")
        }
    }
}

/// The Wine log of a game's last launch, in LogKit's viewer.
struct WineLogWindow: View {
    @Environment(AppModel.self) private var model
    let gameID: String?
    @State private var viewer: LogViewerModel?

    var body: some View {
        Group {
            if let viewer {
                LogViewer(model: viewer, options: LogViewerOptions(
                    emptyTitle: String(localized: "No Wine Log Yet"),
                    emptyMessage: String(localized: "Wine writes here each time a Windows game starts.")))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "Wine Log — \(model.game(gameID)?.title ?? "")"))
        .frame(minWidth: 640, minHeight: 400)
        .task(id: gameID) {
            guard let gameID else { return }
            let title = model.game(gameID)?.title ?? gameID
            viewer = LogViewerModel(file: LogFileSource(files: [.init(title, url: model.wineLogURL(gameID))],
                                                        folder: Store.wineLogsFolder, parser: WineLog.parser))
        }
    }
}
