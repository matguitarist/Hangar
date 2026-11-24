import HangarKit
import SwiftUI

/// Couch mode (S-028): large covers and large text to use from the sofa, with the keyboard or a controller.
struct CouchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    static let tileWidth: CGFloat = 168

    var body: some View {
        let selected = model.game(model.couch.selected)
        ZStack {
            if model.couch.rows.isEmpty {
                ContentUnavailableView {
                    Label("No games yet", systemImage: "gamecontroller")
                } actions: {
                    Button("Leave Couch Mode") { model.leaveCouchMode() }
                }
            } else {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let selected { CouchHero(game: selected) }
                    rows
                    CouchHints()
                }
                .padding(Space.xxl)
            }
            if model.couchDetails, let selected {
                CouchDetails(game: selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A background, so the blurred cover never makes the page larger than the window.
        .background { CouchBackground(game: selected) }
        .environment(\.colorScheme, .dark)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let direction: CouchDirection = switch press.key {
            case .leftArrow: .left
            case .rightArrow: .right
            case .upArrow: .up
            default: .down
            }
            model.couch(.move(direction))
            return .handled
        }
        .onKeyPress(.return) { model.couch(.play); return .handled }
        .onKeyPress(.escape) { model.couch(.back); return .handled }
        .onKeyPress(.space) { model.couch(.details); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Couch Mode"))
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(Array(model.couch.rows.enumerated()), id: \.offset) { index, ids in
                        VStack(alignment: .leading, spacing: Space.md) {
                            Text(rowTitle(index))
                                .font(.title2.weight(.bold))
                            ScrollViewReader { rowProxy in
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: Space.xl) {
                                        ForEach(ids, id: \.self) { id in
                                            if let game = model.game(id) {
                                                CouchTile(game: game, selected: model.couch.row == index && model.couch.selected == id)
                                                    .id("\(index)-\(id)")
                                                    .onTapGesture {
                                                        model.couch.select(id)
                                                    }
                                            }
                                        }
                                    }
                                    .padding(.vertical, Space.md)
                                    .padding(.horizontal, Space.sm)
                                }
                                .scrollIndicators(.hidden)
                                .onChange(of: model.couch.selected) {
                                    guard model.couch.row == index, let id = model.couch.selected else { return }
                                    withAnimation(.snappy) { rowProxy.scrollTo("\(index)-\(id)", anchor: .center) }
                                }
                            }
                        }
                        .id("row-\(index)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.couch.row) {
                withAnimation(.snappy) { proxy.scrollTo("row-\(model.couch.row)", anchor: .top) }
            }
        }
    }

    private func rowTitle(_ index: Int) -> String {
        // The first row is "Continue Playing" only when someone played something.
        let hasRecent = model.library.games.contains { $0.lastPlayed != nil }
        return index == 0 && hasRecent ? String(localized: "Continue Playing") : String(localized: "All Games")
    }
}

/// The selected game, large: its name, where it comes from, playtime, and what A or Return does.
private struct CouchHero: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(game.title)
                .font(.system(size: 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: Space.md) {
                if let state = model.running[game.id] {
                    Button { model.couch(.play) } label: {
                        Label(state.phase == .starting ? String(localized: "Starting…") : String(localized: "Stop…"), systemImage: "stop.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .controlSize(.extraLarge)
                } else {
                    Button { model.couch(.play) } label: {
                        Label("Play", systemImage: "play.fill").font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                }
                Button { model.couch(.details) } label: {
                    Label("Details", systemImage: "info.circle").font(.title3)
                }
                .controlSize(.extraLarge)
            }
            .padding(.top, Space.sm)
        }
    }

    private var subtitle: String {
        var parts = [game.sourceLabel]
        if let state = model.running[game.id] {
            parts.append(state.phase == .starting ? String(localized: "Starting…") : String(localized: "Running"))
        }
        parts.append(game.playtime > 0 ? String(localized: "Played \(PlaytimeText.short(game.playtime))") : String(localized: "Not played yet"))
        return parts.joined(separator: " · ")
    }
}

/// A cover in a couch row; the selected one grows and gets the accent ring.
private struct CouchTile: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let selected: Bool

    var body: some View {
        GameCover(game: game)
            .frame(width: CouchView.tileWidth)
            .overlay(alignment: .topTrailing) {
                if model.running[game.id] != nil {
                    Label("Running", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.accent, in: Capsule())
                        .padding(Space.sm)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Color.clear, lineWidth: 4)
                    .padding(-4)
            }
            .scaleEffect(selected ? 1.08 : 1)
            .shadow(color: .black.opacity(selected ? 0.5 : 0), radius: 16, y: 8)
            .animation(.snappy, value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(game.title))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected cover, blurred and darkened, behind everything.
private struct CouchBackground: View {
    let game: Game?

    var body: some View {
        ZStack {
            Color.black
            if let game {
                GameCover(game: game)
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.55)
                    .id(game.id)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The selected game's details over couch mode (Y or Space).
private struct CouchDetails: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { model.couchDetails = false }
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(game.title).font(.largeTitle.weight(.bold))
                if case let .some(.some(details)) = model.details[game.id], !details.summary.isEmpty {
                    Text(details.summary)
                        .font(.title3)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                    if !details.developers.isEmpty {
                        LabeledContent("Developer", value: ListFormatter.localizedString(byJoining: details.developers))
                            .font(.title3)
                    }
                }
                LabeledContent("Playtime", value: game.playtime > 0 ? PlaytimeText.short(game.playtime) : String(localized: "Not played yet"))
                    .font(.title3)
                LabeledContent("Last played", value: game.lastPlayed.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Never"))
                    .font(.title3)
            }
            .padding(Space.xxl)
            .frame(maxWidth: 720, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .padding(Space.xxl)
        }
        .transition(.opacity)
    }
}
