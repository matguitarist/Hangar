import HangarKit
import SwiftUI

/// The bar at the bottom of couch mode: what each button or key does, named in words, not only glyphs.
/// With a controller connected, its own glyphs (a cross on a DualSense, A on an Xbox pad).
struct CouchHints: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.xl) {
            if model.controllers.name != nil {
                ForEach(controllerHints, id: \.label) { hint in
                    HStack(spacing: Space.sm) {
                        Image(systemName: hint.symbol).font(.title2)
                        Text(hint.label).font(.title3)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ForEach(Self.keyboard, id: \.label) { hint in
                    HStack(spacing: Space.sm) {
                        Text(hint.key)
                            .font(.callout.weight(.semibold).monospaced())
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .rect(cornerRadius: Radius.control / 2, style: .continuous))
                        Text(hint.label).font(.title3)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    struct Hint { let key: String; let label: String }
    struct Glyph { let symbol: String; let label: String }

    private var controllerHints: [Glyph] {
        let glyphs = model.controllers.glyphs
        return [Glyph(symbol: "dpad", label: String(localized: "Move")),
                Glyph(symbol: glyphs[.a] ?? "a.circle", label: String(localized: "Play")),
                Glyph(symbol: glyphs[.y] ?? "y.circle", label: String(localized: "Details")),
                Glyph(symbol: glyphs[.b] ?? "b.circle", label: String(localized: "Back"))]
    }

    static var keyboard: [Hint] {
        [Hint(key: "←→↑↓", label: String(localized: "Move")),
         Hint(key: "↩", label: String(localized: "Play")),
         Hint(key: String(localized: "Space"), label: String(localized: "Details")),
         Hint(key: "esc", label: String(localized: "Back"))]
    }
}

/// "Controller connected", for a moment, over whatever Hangar shows.
struct ControllerToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.controllers.justConnected {
            Label("Controller connected", systemImage: "gamecontroller.fill")
                .font(.headline)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, Space.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
