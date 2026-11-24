import SwiftUI

/// The bar at the bottom of couch mode: what each key does, named in words, not only glyphs.
struct CouchHints: View {
    var body: some View {
        HStack(spacing: Space.xl) {
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
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    struct Hint { let key: String; let label: String }

    static var keyboard: [Hint] {
        [Hint(key: "←→↑↓", label: String(localized: "Move")),
         Hint(key: "↩", label: String(localized: "Play")),
         Hint(key: String(localized: "Space"), label: String(localized: "Details")),
         Hint(key: "esc", label: String(localized: "Back"))]
    }
}
