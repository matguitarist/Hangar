import AppKit
import HangarKit
import SwiftUI
import UniformTypeIdentifiers

/// The game page's Launch Options: the program a Windows game runs, its arguments, and environment variables.
struct LaunchOptionsSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Section {
            if game.runner == .crossOver, game.steamID == nil, let bottle = game.bottle {
                LabeledContent("Program") {
                    HStack(spacing: Space.sm) {
                        Text(programName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(game.options.exe ?? game.exe ?? "")
                        Button("Choose…") { choose(bottle: bottle) }
                        if game.options.exe != nil {
                            Button("Reset") { model.setOptions(game.id) { $0.exe = nil } }
                        }
                    }
                }
            }
            TextField("Arguments", text: Binding(get: { game.options.arguments },
                                                 set: { text in model.setOptions(game.id) { $0.arguments = text } }),
                      prompt: Text(verbatim: "-windowed -novid"))
                .help(String(localized: "Words passed to the game when it starts. Quote a word with spaces."))
            ForEach(game.options.variables) { variable in
                VariableRow(game: game, variable: variable)
            }
            Button("Add Variable") {
                model.setOptions(game.id) { $0.variables.append(EnvironmentVariable(name: "", value: "")) }
            }
            .help(String(localized: "Add an environment variable for this game"))
        } header: {
            Text("Launch Options")
        } footer: {
            if game.source == .steam, game.runner == .native, !(game.options.arguments.isEmpty && game.options.variables.isEmpty) {
                Text("Steam can't pass these on, so Hangar opens the game itself, without Steam's overlay.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var programName: String {
        let path = game.options.exe ?? game.exe ?? ""
        let name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? path
        return game.options.exe == nil && game.startsShortcut ? String(localized: "\(name) (shortcut)") : name
    }

    private func choose(bottle: String) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Program")
        panel.prompt = String(localized: "Choose")
        panel.allowedContentTypes = [.exe]
        let root = model.bottleURL(bottle)
        panel.directoryURL = URL(fileURLWithPath: game.path).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let windows = LaunchPlanner.windowsPath(for: url, bottle: root)
        model.setOptions(game.id) { $0.exe = windows }
    }
}

/// NAME = value, with a button to remove it.
private struct VariableRow: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let variable: EnvironmentVariable

    var body: some View {
        HStack(spacing: Space.sm) {
            TextField("Name", text: binding(\.name), prompt: Text(verbatim: "DXVK_HUD"))
                .labelsHidden()
                .font(.body.monospaced())
            Text(verbatim: "=").foregroundStyle(.secondary)
            TextField("Value", text: binding(\.value), prompt: Text("Value"))
                .labelsHidden()
                .font(.body.monospaced())
            Button {
                model.setOptions(game.id) { $0.variables.removeAll { $0.id == variable.id } }
            } label: {
                Label("Remove Variable", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(String(localized: "Remove this variable"))
        }
    }

    private func binding(_ path: WritableKeyPath<EnvironmentVariable, String>) -> Binding<String> {
        Binding(get: { variable[keyPath: path] }, set: { text in
            model.setOptions(game.id) { options in
                if let i = options.variables.firstIndex(where: { $0.id == variable.id }) { options.variables[i][keyPath: path] = text }
            }
        })
    }
}

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
}
