import HangarKit
import SwiftUI

/// The game page's Settings tab.
struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Form {
            if let settings = model.bottleSettings(for: game), let bottle = game.bottle {
                BottleSettingsSection(game: game, bottle: bottle, settings: settings)
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
