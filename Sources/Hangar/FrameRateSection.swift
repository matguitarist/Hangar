import AppKit
import HangarKit
import SwiftUI

/// Frame Rate (S-038): a limit for a Windows game run with DXVK, for a cooler, quieter Mac.
struct FrameRateSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let usesDXVK = model.frameCapBackend(game) == .dxvk
        Section {
            FrameCapPicker(title: String(localized: "Limit"), selection: Binding(get: { game.options.frameCap },
                                                                               set: { cap in model.setOptions(game.id) { $0.frameCap = cap } }))
                .disabled(!usesDXVK)
                .help(String(localized: "Keep the game at or under this frame rate"))
        } header: {
            Text("Frame Rate")
        } footer: {
            Text(usesDXVK ? String(localized: "Fewer frames keep the Mac cooler and quieter, and the battery lasts longer.")
                          : String(localized: "Only DXVK games can be capped. Set Graphics to DXVK to use it."))
                .foregroundStyle(.secondary)
        }
    }
}

/// Off, 30, 40, 60, or the display's rate.
struct FrameCapPicker: View {
    let title: String
    @Binding var selection: Int?

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(FrameCap.choices, id: \.self) { cap in
                Text(Self.label(cap)).tag(cap)
            }
        }
    }

    static func label(_ cap: Int?) -> String {
        switch cap {
        case nil: String(localized: "Off")
        case 0: String(localized: "Display (\(NSScreen.main?.maximumFramesPerSecond ?? 60) Hz)")
        case let .some(fps): String(localized: "\(fps) fps")
        }
    }
}
