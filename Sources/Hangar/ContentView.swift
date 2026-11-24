import AppKit
import HangarKit
import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            page(model.sidebar ?? .allGames)
        }
        .toolbar(model.couchMode ? .hidden : .automatic, for: .windowToolbar)
        .overlay {
            if model.couchMode {
                CouchView()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.couchMode)
        .sheet(item: $model.addRequest) { request in
            AddGameSheet(request: request)
        }
        .sheet(isPresented: Binding(get: { model.previewingRecipe != nil }, set: { if !$0 { model.previewingRecipe = nil } })) {
            if let id = model.previewingRecipe { RecipeSheet(gameID: id) }
        }
        .sheet(isPresented: Binding(get: { model.showsBackups != nil }, set: { if !$0 { model.showsBackups = nil } })) {
            if let id = model.showsBackups { BackupsSheet(gameID: id) }
        }
        .sheet(isPresented: Binding(get: { model.showsSnapshots != nil }, set: { if !$0 { model.showsSnapshots = nil } })) {
            if let id = model.showsSnapshots { SnapshotsSheet(gameID: id) }
        }
        .confirmationDialog(stopTitle, isPresented: Binding(get: { model.confirmingStop != nil }, set: { if !$0 { model.confirmingStop = nil } })) {
            Button("Stop", role: .destructive) { if let id = model.confirmingStop { model.stop(id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved progress in the game will be lost.")
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .task {
            await model.refresh()
            SeedData.addIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
    }

    private var stopTitle: String {
        String(localized: "Stop \(model.game(model.confirmingStop)?.title ?? "")?")
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Lines Yet"),
                emptyMessage: String(localized: "What Hangar does, such as finding and launching games, is written here.")))
                .navigationTitle("Log")
        case .runners:
            RunnersPage()
        default:
            LibraryView(item: item)
        }
    }
}

/// Seed mode for snapshots: playtime, a collection and a running game on top of the sample library.
enum SeedData {
    static func addIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden else { return }
        let now = Date()
        func set(_ title: String, hours: Double, daysAgo: Double) {
            guard let index = model.library.games.firstIndex(where: { $0.title == title }) else { return }
            model.library.games[index].playtime = hours * 3600
            model.library.games[index].lastPlayed = now.addingTimeInterval(-daysAgo * 86400)
        }
        set("Hollow Knight", hours: 42.6, daysAgo: 2)
        set("Vernal Edge", hours: 3.34, daysAgo: 0.2)
        set("Stardew Valley", hours: 118, daysAgo: 9)
        set("Starfall Arcade", hours: 0.75, daysAgo: 30)
        let couch = model.library.games.filter { ["Stardew Valley", "Kynseed", "Starfall Arcade"].contains($0.title) }.map(\.id)
        if model.library.collections.isEmpty {
            model.library.collections = [GameCollection(name: String(localized: "Couch Co-op"), gameIDs: couch),
                                         GameCollection(name: String(localized: "Metroidvanias"), gameIDs: [])]
        }
        if let bloodstained = model.library.games.first(where: { $0.title.hasPrefix("Bloodstained") }) {
            model.running[bloodstained.id] = LaunchState(phase: .running, launched: now.addingTimeInterval(-1200), started: now.addingTimeInterval(-1190))
        }
        model.log.post(.info, "Found 9 games", source: "Library")
        model.log.post(.warning, "The Steam library at /Volumes/Data/SteamLibrary isn't connected", source: "Library")
        model.log.post(.info, "Starting Vernal Edge: wine --bottle Steam --cx-app steam.exe -silent -applaunch 1546710", source: "Launch")
        model.log.post(.error, "Kynseed quit after 4 seconds", source: "Launch")
    }
}
