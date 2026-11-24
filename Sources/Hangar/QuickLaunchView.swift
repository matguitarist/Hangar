import AppKit
import HangarKit
import SwiftUI

/// The menu bar's panel (S-026): what's running, and the games played last, one click from playing.
struct QuickLaunchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    /// Closes the panel (the menu bar extra's window) before acting.
    var close: () -> Void = { NSApp.keyWindow?.close() }

    var body: some View {
        let runningGames = model.library.games.filter { model.running[$0.id] != nil }
            .sorted { (model.running[$0.id]?.launched ?? .distantPast) > (model.running[$1.id]?.launched ?? .distantPast) }
        let recent = QuickLaunch.recent(model.library.games, running: Set(model.running.keys))
        VStack(alignment: .leading, spacing: 2) {
            if !runningGames.isEmpty {
                header("Running")
                ForEach(runningGames) { game in runningRow(game) }
            }
            if !recent.isEmpty {
                header("Recently Played")
                ForEach(recent) { game in
                    PanelRow(help: String(localized: "Play \(game.title)")) {
                        close()
                        model.play(game.id)
                    } label: {
                        GameLine(game: game, detail: game.lastPlayed.map {
                            String(localized: "Played \($0.formatted(.relative(presentation: .named)))")
                        } ?? "")
                    }
                }
            }
            if runningGames.isEmpty && recent.isEmpty {
                Text("The games you play show here.")
                    .foregroundStyle(.secondary)
                    .padding(Space.sm)
            }
            Divider().padding(.vertical, Space.xs)
            PanelRow(help: String(localized: "Show the library")) {
                close()
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Text("Open Hangar")
            }
            PanelRow(help: String(localized: "Quit Hangar (⌘Q)")) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Hangar")
            }
        }
        .padding(Space.sm)
        .frame(width: 300)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.sm)
            .padding(.top, Space.xs)
    }

    private func runningRow(_ game: Game) -> some View {
        let state = model.running[game.id]
        let detail = state?.phase == .starting ? String(localized: "Starting…")
            : String(localized: "Playing since \((state?.started ?? state?.launched ?? Date()).formatted(date: .omitted, time: .shortened))")
        return HStack(spacing: Space.xs) {
            PanelRow(help: String(localized: "Bring \(game.title) to the front")) {
                close()
                bringForward(game, state)
            } label: {
                GameLine(game: game, detail: detail)
            }
            Button("Stop…") {
                close()
                openWindow(id: "main")
                NSApp.activate()
                model.confirmingStop = game.id
            }
            .help(String(localized: "Stop \(game.title)"))
            .padding(.trailing, Space.xs)
        }
    }

    /// The game's own window if macOS knows its app; else its page in Hangar.
    private func bringForward(_ game: Game, _ state: LaunchState?) {
        if let app = state?.pids.lazy.compactMap({ NSRunningApplication(processIdentifier: $0) }).first(where: { $0.activationPolicy == .regular }) {
            app.activate()
            return
        }
        model.sidebar = .running
        model.selectedGameID = game.id
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// A cover, a title and one line under it.
private struct GameLine: View {
    let game: Game
    let detail: String

    var body: some View {
        HStack(spacing: Space.sm) {
            GameCover(game: game)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A row of the panel that highlights under the pointer or with keyboard focus, like a menu item.
private struct PanelRow<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label

    init(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelRowStyle())
        .focusEffectDisabled()
        .help(help)
    }
}

private struct PanelRowStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(hovering || focused || configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: Radius.control, style: .continuous))
            .contentShape(.rect)
            .onHover { hovering = $0 }
    }
}
