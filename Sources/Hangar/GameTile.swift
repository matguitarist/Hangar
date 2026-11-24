import AppKit
import HangarKit
import SwiftUI

/// A game in the grid: its cover, title, and where it comes from.
struct GameTile: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GameCover(game: game)
                .overlay(alignment: .topTrailing) { runningBadge }
                .overlay(alignment: .bottomLeading) {
                    if game.isWindows {
                        Text("Windows")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .padding(Space.sm)
                            .help(game.bottle.map { String(localized: "Runs in CrossOver, bottle \($0)") } ?? "CrossOver")
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? Palette.accent : Color.clear, lineWidth: 4)
                        .padding(-4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(game.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var subtitle: String {
        game.playtime > 0 ? "\(game.sourceLabel) · \(PlaytimeText.short(game.playtime))" : game.sourceLabel
    }

    private var accessibilityText: String {
        var parts = [game.title, game.sourceLabel]
        if game.isWindows { parts.append(String(localized: "Windows game, bottle \(game.bottle ?? "")")) }
        if game.playtime > 0 { parts.append(String(localized: "played \(PlaytimeText.short(game.playtime))")) }
        if model.running[game.id] != nil { parts.append(String(localized: "Running")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var runningBadge: some View {
        if let state = model.running[game.id] {
            Group {
                if state.phase == .starting {
                    Label("Starting…", systemImage: "hourglass")
                } else {
                    Label("Running", systemImage: "play.fill")
                }
            }
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(Palette.accent, in: Capsule())
            .padding(Space.sm)
        }
    }
}

/// A game's cover: the chosen image, Steam's art, the app's icon, or a generated cover.
struct GameCover: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    GeneratedCoverView(game: game)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(.separator, lineWidth: 1)
            }
            .accessibilityHidden(true)
            .task(id: "\(game.id)|\(game.customCover ?? "")|\(model.coverGeneration)") { image = await load() }
    }

    private func load() async -> NSImage? {
        if let custom = game.customCover, let image = NSImage(contentsOfFile: custom) { return image }
        guard let id = game.steamID else {
            // A Windows game that isn't on Steam: SteamGridDB by name, with a key.
            // A Mac app keeps its own icon on the generated cover.
            guard game.isWindows, let file = await model.covers.cover(title: game.title) else { return nil }
            return NSImage(contentsOf: file)
        }
        guard let file = await model.covers.cover(steamID: id) else {
            model.log.post(.debug, "No Steam cover for \(game.title), the generated one shows", source: "Covers")
            return nil
        }
        return NSImage(contentsOf: file)
    }
}

/// The cover drawn when there's no art: the title on a color from the name,
/// or a Mac app's icon on that color. The hue is computed from the title, not a fixed color.
struct GeneratedCoverView: View {
    let game: Game

    var body: some View {
        let hue = GeneratedCover.hue(for: game.title)
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.62),
                                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if game.runner == .native, game.path.hasSuffix(".app") {
                VStack(spacing: Space.md) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: game.path))
                        .resizable()
                        .frame(width: 72, height: 72)
                    title
                }
            } else {
                title
            }
        }
    }

    private var title: some View {
        Text(game.title)
            .font(.title3.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .lineLimit(4)
            .minimumScaleFactor(0.7)
            .padding(Space.md)
    }
}
