import HangarKit
import SwiftUI

/// The game page's Settings tab.
struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Form {
            if game.runner == .crossOver, game.steamID == nil {
                RunnerSection(game: game)
            }
            if game.options.runner == nil, let settings = model.bottleSettings(for: game), let bottle = game.bottle {
                BottleSettingsSection(game: game, bottle: bottle, settings: settings)
            }
            Section {
                Toggle("Metal Performance HUD", isOn: Binding(get: { game.options.metalHUD },
                                                               set: { on in model.setOptions(game.id) { $0.metalHUD = on } }))
                    .help(String(localized: "Show frame rate, GPU time and memory over the game"))
            } footer: {
                Text(hudFooter).foregroundStyle(.secondary)
            }
            LaunchOptionsSection(game: game)
        }
        .formStyle(.grouped)
        .id(model.settingsGeneration)
        .confirmationDialog(String(localized: "Give \(game.title) its own bottle?"),
                            isPresented: Binding(get: { model.confirmingOwnBottle == game.id }, set: { if !$0 { model.confirmingOwnBottle = nil } })) {
            Button("Copy Bottle") { Task { await model.giveOwnBottle(game.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hangar copies the bottle \(game.bottle ?? "") and moves \(game.title) to the copy. The other games stay in the bottle \(game.bottle ?? "") as they are.")
        }
    }
}

extension GameSettingsView {
    var hudFooter: String {
        if game.source == .steam, game.runner == .native {
            return String(localized: "Shows the next time the game starts. Steam can't pass the HUD on, so Hangar opens the game itself, without Steam's overlay.")
        }
        return String(localized: "Shows the next time the game starts.")
    }
}

/// CrossOver in the game's bottle, or a Wine build or Game Porting Toolkit in a prefix of its own.
private struct RunnerSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let others = model.runners.filter(\.runsPrefixes)
        Section {
            Picker("Runner", selection: Binding(get: { game.options.runner }, set: { path in model.setOptions(game.id) { $0.runner = path } })) {
                Text("CrossOver, bottle \(game.bottle ?? "")").tag(String?.none)
                ForEach(others) { runner in
                    Text(runner.version.map { "\(runner.name) \($0)" } ?? runner.name).tag(Optional(runner.path))
                }
                if let path = game.options.runner, !others.contains(where: { $0.path == path }) {
                    Text("Not installed anymore").tag(Optional(path))
                }
            }
            .help(String(localized: "What runs this game"))
        } footer: {
            if game.options.runner != nil {
                Text("Runs in a prefix of its own, from the game's files in the bottle \(game.bottle ?? ""). The bottle's settings don't apply.")
                    .foregroundStyle(.secondary)
            } else if others.isEmpty {
                Text("Install a Wine build or Game Porting Toolkit to run this game outside CrossOver.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Graphics, MSync, High Resolution Mode, MetalFX and AVX: CrossOver's settings for the whole bottle.
private struct BottleSettingsSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let bottle: String
    let settings: BottleSettings

    var body: some View {
        let busy = model.bottleIsBusy(bottle)
        let mates = model.bottleMates(of: game)
        Section {
            if !mates.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    let names = ListFormatter.localizedString(byJoining: mates.map(\.title))
                    Label(mates.count == 1 ? String(localized: "\(names) also runs in this bottle. These settings change it too.")
                                           : String(localized: "\(names) also run in this bottle. These settings change them too."),
                          systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                    if model.copyingBottle == game.id {
                        HStack(spacing: Space.sm) {
                            ProgressView().controlSize(.small)
                            Text("Copying the bottle…").foregroundStyle(.secondary)
                        }
                    } else {
                        Button(String(localized: "Give \(game.title) Its Own Bottle…")) { model.confirmingOwnBottle = game.id }
                            .help(String(localized: "Copy the bottle, so its settings change this game alone"))
                    }
                }
            }
            Picker("Graphics", selection: binding(\.graphics)) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .help(String(localized: "How the game's graphics reach Metal. Auto lets CrossOver choose."))
            Toggle("MSync", isOn: binding(\.msync))
                .help(String(localized: "Faster syncing between the game's threads. Most games run better with it on."))
            Toggle("High Resolution Mode", isOn: binding(\.highResolution))
                .help(String(localized: "Draws the game at the full resolution of a Retina display. Demanding games run slower."))
            Toggle("MetalFX", isOn: binding(\.metalFX))
                .help(String(localized: "Lets D3DMetal games upscale with MetalFX."))
            Toggle("AVX for Rosetta", isOn: binding(\.avx))
                .help(String(localized: "Tells games that Rosetta can run AVX instructions. Some newer games need it."))
        } header: {
            Text("Bottle \(bottle)")
        } footer: {
            Text(busy ? String(localized: "Quit the games in this bottle to change its settings.")
                      : String(localized: "These settings change the bottle \(bottle), for every game in it."))
                .foregroundStyle(.secondary)
        }
        .disabled(busy)
    }

    private func binding<Value>(_ path: WritableKeyPath<BottleSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: path] }, set: { value in
            var new = settings
            new[keyPath: path] = value
            model.changeBottleSettings(game.id, to: new)
        })
    }
}
