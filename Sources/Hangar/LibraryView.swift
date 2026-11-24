import HangarKit
import SwiftUI

/// A page of games as a cover grid, with the game page in the inspector.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    @State private var width: CGFloat = 800
    @State private var dropTargeted = false
    @FocusState private var gridFocused: Bool
    @FocusState private var searchFocused: Bool

    static let tileWidth: CGFloat = 148
    static let spacing = Space.xl

    var body: some View {
        @Bindable var model = model
        let games = model.games(for: item)
        ScrollView {
            if item == .allGames, !model.runnerUpdates.isEmpty {
                VStack(spacing: Space.md) {
                    ForEach(model.runnerUpdates) { RunnerUpdateBanner(notice: $0) }
                }
                .padding([.horizontal, .top], Space.margin)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth, maximum: 200), spacing: Self.spacing, alignment: .top)],
                      alignment: .leading, spacing: Space.xxl) {
                ForEach(games) { game in
                    GameTile(game: game, selected: model.selectedGameID == game.id)
                        .contentShape(.rect)
                        .gesture(TapGesture(count: 2).onEnded { model.play(game.id) })
                        .simultaneousGesture(TapGesture().onEnded { model.selectedGameID = game.id; gridFocused = true })
                        .draggable(game.id)
                        .contextMenu { GameMenu(game: game, page: item) }
                }
            }
            .padding(Space.margin)
            .gridArea("grid")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            move(press.key, in: games)
            return .handled
        }
        .onKeyPress(.return) {
            guard let id = model.selectedGameID else { return .ignored }
            model.play(id)
            return .handled
        }
        .onKeyPress(.space) {
            guard model.selectedGameID != nil else { return .ignored }
            model.showsGamePage.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            if model.showsGamePage { model.showsGamePage = false } else { model.selectedGameID = nil }
            return .handled
        }
        .overlay { emptyState(games) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 4)
                    .padding(Space.sm)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(files: urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .navigationTitle(model.pageTitle(item))
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search Games"))
        .searchFocused($searchFocused)
        .onChange(of: model.focusSearch) { searchFocused = true }
        .toolbar { toolbar }
        .inspector(isPresented: $model.showsGamePage) {
            GamePage(gameID: model.selectedGameID)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.showsScanning {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Looking for games…").foregroundStyle(.secondary)
                }
            }
            Menu {
                Picker("Sort By", selection: Binding(get: { model.sort }, set: { model.sort = $0 })) {
                    ForEach(GameSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .help(String(localized: "Sort games"))
            Button { GamePanels.addGame(model) } label: { Label("Add Game", systemImage: "plus") }
                .help(String(localized: "Add a game (⌘N)"))
        }
    }

    @ViewBuilder
    private func emptyState(_ games: [Game]) -> some View {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        if games.isEmpty {
            if !query.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No games match “\(query)”"), systemImage: "magnifyingglass")
                } actions: {
                    Button("Clear Search") { model.searchText = "" }
                }
            } else if case .collection = item {
                ContentUnavailableView("Drag games here to add them", systemImage: "rectangle.stack")
            } else if case .bottle = item {
                ContentUnavailableView("No games in this bottle", systemImage: "shippingbox")
            } else if item == .running {
                ContentUnavailableView("No game is running", systemImage: "play.circle")
            } else if model.hasScanned {
                ContentUnavailableView {
                    Label("No Games Found", systemImage: "gamecontroller")
                } description: {
                    Text("Hangar looks in Steam, CrossOver bottles and the Applications folders. Add a game yourself, or show Hangar where Steam is.")
                } actions: {
                    Button("Add Game…") { GamePanels.addGame(model) }
                    Button("Choose Steam Folder…") { GamePanels.chooseSteamFolder(model) }
                }
            }
        }
    }

    /// Arrow keys move the selection through the grid, a row at a time up and down.
    private func move(_ key: KeyEquivalent, in games: [Game]) {
        guard !games.isEmpty else { return }
        let columns = max(1, Int((width - 2 * Space.margin + Self.spacing) / (Self.tileWidth + Self.spacing)))
        let current = games.firstIndex { $0.id == model.selectedGameID }
        var index = current ?? 0
        if current != nil {
            switch key {
            case .leftArrow: index -= 1
            case .rightArrow: index += 1
            case .upArrow: index -= columns
            default: index += columns
            }
        }
        model.selectedGameID = games[min(max(index, 0), games.count - 1)].id
    }
}

/// The context menu of a game, in the grid and the sidebar.
struct GameMenu: View {
    @Environment(AppModel.self) private var model
    let game: Game
    var page: SidebarItem = .allGames

    var body: some View {
        if model.running[game.id] == nil {
            Button("Play") { model.play(game.id) }
        } else {
            Button("Stop…") { model.confirmingStop = game.id }
        }
        Divider()
        Button("Show in Finder") { model.showInFinder(game.id) }
        if game.storeURL != nil { Button("Open Store Page") { model.openStorePage(game.id) } }
        Divider()
        Menu("Add to Collection") {
            ForEach(model.library.collections) { collection in
                Button(collection.name) { model.addToCollection([game.id], collection.id) }
            }
            if !model.library.collections.isEmpty { Divider() }
            Button("New Collection") { model.newCollection(with: [game.id]) }
        }
        if case let .collection(id) = page {
            Button("Remove from Collection") { model.removeFromCollection([game.id], id) }
        }
        Divider()
        Button("Choose Cover…") { GamePanels.chooseCover(model, game.id) }
        if game.customCover != nil { Button("Reset Cover") { model.resetCover(game.id) } }
        Divider()
        Button("Remove from Library") { model.remove(game.id) }
    }
}
