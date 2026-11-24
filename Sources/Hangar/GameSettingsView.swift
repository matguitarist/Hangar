import HangarKit
import SwiftUI

/// The game page's Settings tab.
struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Form {
            if game.isHeroic {
                HeroicSection(game: game)
            } else {
                sections
            }
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
        .confirmationDialog(String(localized: "Share the setup of \(game.title)?"),
                            isPresented: Binding(get: { model.sharingRecipe == game.id }, set: { if !$0 { model.sharingRecipe = nil } })) {
            Button("Copy and Open GitHub") { model.shareRecipe(game.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hangar copies the recipe and opens a new issue on GitHub with it. Nothing is sent until you submit the issue there.")
        }
    }
}

extension GameSettingsView {
    @ViewBuilder
    var sections: some View {
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
        if game.runner == .crossOver, game.bottle != nil {
            FrameRateSection(game: game)
        }
        if Power.hasBattery {
            BatterySection(game: game)
        }
        LaunchOptionsSection(game: game)
        Section {
            let list = model.snapshotList(game.id)
            LabeledContent("Snapshots") {
                Text(list.isEmpty ? String(localized: "None yet") : list.first(where: { $0.worked != nil })?.title ?? list[0].title)
                    .foregroundStyle(.secondary)
            }
            Button("Show Snapshots…") { model.showsSnapshots = game.id }
                .help(String(localized: "Go back to settings that worked"))
        } footer: {
            Text("Saved before every change and every launch.").foregroundStyle(.secondary)
        }
        if game.runner == .crossOver, game.bottle != nil {
            Section {
                Button("Share This Setup…") { model.sharingRecipe = game.id }
                    .help(String(localized: "Send these settings as a recipe, so others can play this game too"))
            } footer: {
                Text("Sends the settings as a recipe on Hangar's GitHub, never your files or your user name.").foregroundStyle(.secondary)
            }
        }
    }

    var hudFooter: String {
        if game.source == .steam, game.runner == .native {
            return String(localized: "Shows the next time the game starts. Steam can't pass the HUD on, so Hangar opens the game itself, without Steam's overlay.")
        }
        return String(localized: "Shows the next time the game starts.")
    }
}

/// CrossOver in the game's bottle, or a Wine build or Game Porting Toolkit in a prefix of its own.
/// On Battery (S-025): other settings when the Mac is unplugged at launch.
private struct BatterySection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Section {
            Toggle("Use other settings on battery", isOn: Binding(get: { game.options.battery != nil },
                                                                  set: { model.useBatteryProfile(game.id, $0) }))
            if game.options.battery != nil {
                Toggle("Metal Performance HUD", isOn: binding(\.metalHUD))
                    .help(String(localized: "Show the HUD on battery, whatever the setting above"))
                Toggle("Lower the display resolution", isOn: binding(\.lowerResolution))
                    .help(String(localized: "Play at the next resolution down, back to normal when the game quits"))
                Toggle("Suggest Low Power Mode", isOn: binding(\.suggestLowPowerMode))
                    .help(String(localized: "When it's off at launch, show a reminder with a link to Battery settings"))
                if model.frameCapBackend(game) == .dxvk {
                    FrameCapPicker(title: String(localized: "Limit the frame rate to"),
                                   selection: Binding(get: { game.options.battery?.frameCap },
                                                      set: { cap in model.setOptions(game.id) { $0.battery?.frameCap = cap } }))
                        .help(String(localized: "On battery, in place of the game's own limit"))
                }
            }
        } header: {
            Text("On Battery")
        } footer: {
            Text(game.options.battery == nil
                 ? String(localized: "Play longer unplugged: these settings apply when the Mac is on battery at launch.")
                 : String(localized: "Used when the Mac is on battery at launch. Hangar can't turn on Low Power Mode itself, so it reminds you."))
                .foregroundStyle(.secondary)
        }
    }

    private func binding(_ key: WritableKeyPath<BatteryProfile, Bool>) -> Binding<Bool> {
        Binding(get: { game.options.battery?[keyPath: key] ?? false },
                set: { on in model.setOptions(game.id) { $0.battery?[keyPath: key] = on } })
    }
}

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

/// A game Heroic installed (S-036): Heroic keeps its Wine settings and starts it.
private struct HeroicSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Section {
            LabeledContent("Runner", value: "Heroic")
            Button("Open in Heroic") { model.openHeroic() }
                .help(String(localized: "Change this game's Wine version, prefix and other settings in Heroic"))
        } footer: {
            Text(game.isWindows ? String(localized: "Heroic keeps this game's Wine settings. Change them in Heroic.")
                                : String(localized: "Heroic starts this game. Change its settings in Heroic."))
                .foregroundStyle(.secondary)
        }
    }
}
