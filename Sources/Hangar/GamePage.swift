import AppKit
import HangarKit
import SwiftUI

/// The game page, beside the grid: cover, what it is, how it runs, and what to do with it.
struct GamePage: View {
    @Environment(AppModel.self) private var model
    let gameID: String?

    var body: some View {
        if let game = model.game(gameID) {
            @Bindable var model = model
            VStack(spacing: 0) {
                Picker("Page", selection: $model.gamePageTab) {
                    ForEach(GamePageTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, Space.sm)
                switch model.gamePageTab {
                case .overview: page(game)
                case .settings: GameSettingsView(game: game)
                }
            }
        } else {
            ContentUnavailableView("Select a game to see its details", systemImage: "gamecontroller")
        }
    }

    private func page(_ game: Game) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.md) {
                    GameCover(game: game)
                        .frame(maxWidth: 160)
                        .frame(maxWidth: .infinity)
                    Text(game.title)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: Space.sm) {
                        Tag(text: game.sourceLabel, symbol: game.source.symbol)
                        if game.isWindows { Tag(text: String(localized: "Windows"), symbol: "pc") }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    actions(game)
                }
                .padding(.vertical, Space.xs)
            }
            banners(game)
            RecipeSection(game: game)
            CompatibilitySection(game: game)
            Section {
                LabeledContent("Source", value: game.sourceLabel)
                LabeledContent("Runner", value: model.runnerLabel(game))
                LabeledContent("Location") {
                    Text(game.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(game.path)
                }
                LabeledContent("Playtime", value: playtime(game))
                LabeledContent("Last played", value: game.lastPlayed.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Never"))
            }
            LinksSection(game: game)
        }
        .formStyle(.grouped)
        // Snapshot mode shows the end of the page.
        .defaultScrollAnchor(model.scrollGamePageToEnd ? .bottom : .top)
        .gridArea("game-page", inset: 0)
    }

    private func playtime(_ game: Game) -> String {
        guard let state = model.running[game.id], let started = state.started else {
            return game.playtime > 0 ? PlaytimeText.short(game.playtime) : String(localized: "Not played yet")
        }
        let now = PlaytimeText.short(Date().timeIntervalSince(started))
        return game.playtime > 0 ? String(localized: "\(PlaytimeText.short(game.playtime)), playing for \(now)")
            : String(localized: "Playing for \(now)")
    }

    private func actions(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let state = model.running[game.id] {
                Button { model.confirmingStop = game.id } label: {
                    Label(state.phase == .starting ? String(localized: "Starting…") : String(localized: "Stop"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help(String(localized: "Quit the game (⌘.)"))
            } else {
                Button { model.play(game.id) } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(String(localized: "Start the game (⌘P)"))
            }
            // Side by side when they fit, one above the other when they don't (French is longer).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) { secondaryButtons(game) }
                VStack(alignment: .leading, spacing: Space.sm) { secondaryButtons(game) }
            }
        }
    }

    @ViewBuilder
    private func secondaryButtons(_ game: Game) -> some View {
        Button("Show in Finder") { model.showInFinder(game.id) }
            .fixedSize()
        if game.storeURL != nil {
            Button("Open Store Page") { model.openStorePage(game.id) }
                .fixedSize()
        }
    }

    @ViewBuilder
    private func banners(_ game: Game) -> some View {
        if model.filesMissing(game) {
            Section {
                Label("The game's files aren't at this location anymore.", systemImage: "questionmark.folder")
                HStack {
                    Button("Locate…") { GamePanels.locate(model, game.id) }
                    Button("Remove from Library") { model.remove(game.id) }
                }
            }
        }
        if model.needsSteamSignIn(game), let bottle = game.bottle {
            Section {
                Label(String(localized: "Sign in to Steam in the bottle \(bottle) to play this game."), systemImage: "person.crop.circle.badge.exclamationmark")
                Button("Open Steam") { model.openSteam(bottle: bottle) }
            }
        }
        if let notice = model.notices[game.id] {
            Section {
                switch notice {
                case let .didntStart(reason):
                    Label(String(localized: "\(game.title) didn't start. \(reason)"), systemImage: "exclamationmark.triangle")
                case .quitRightAway:
                    Label(String(localized: "\(game.title) quit right away"), systemImage: "exclamationmark.triangle")
                case let .didntCopy(reason):
                    Label(String(localized: "Hangar couldn't copy the bottle. \(reason)"), systemImage: "exclamationmark.triangle")
                case .askWorked:
                    Label(String(localized: "Did \(game.title) run well?"), systemImage: "questionmark.circle")
                }
                if notice == .askWorked {
                    HStack(spacing: Space.sm) {
                        Button("It Worked") { model.markWorked(game.id) }
                            .help(String(localized: "Label the settings it started with, to come back to them later"))
                        Button("Not Now") { model.notices[game.id] = nil }
                    }
                } else {
                    Button("Show Details") { model.sidebar = .log }
                }
            }
        }
    }
}
