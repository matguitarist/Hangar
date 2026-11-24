import AppKit
import Combine
import HangarKit
import SwiftUI
import UniformTypeIdentifiers

/// The selection, mirrored for the menu bar: Commands don't observe @Observable models.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var hasSelection = false
    @Published var isRunning = false
    @Published var hasStorePage = false
    @Published var hasCustomCover = false
    @Published var sort: GameSort = .name
    @Published var filter: GameFilter?
    @Published var isFetchingDetails = false
}

extension GameSort {
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .recentlyPlayed: String(localized: "Recently Played")
        case .playtime: String(localized: "Playtime")
        }
    }
}

struct HangarCommands: Commands {
    let model: AppModel
    @ObservedObject var menu: MenuState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Game…") { GamePanels.addGame(model) }
                .keyboardShortcut("n")
            Button("New Collection") { model.newCollection() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        // Game › Play takes Command-P: Hangar has nothing to print.
        CommandGroup(replacing: .printItem) {}
        CommandGroup(after: .textEditing) {
            Button("Search Games") { model.focusSearch += 1 }
                .keyboardShortcut("f")
        }
        CommandGroup(before: .sidebar) {
            Button("Refresh Library") { Task { await model.refresh() } }
                .keyboardShortcut("r")
            if menu.isFetchingDetails {
                Button("Stop Fetching Details") { model.stopFetchingDetails() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            } else {
                Button("Fetch All Details") { model.fetchAllDetails() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
            Picker("Sort By", selection: Binding(get: { menu.sort }, set: { model.sort = $0 })) {
                ForEach(GameSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Filter", selection: Binding(get: { menu.filter }, set: { model.filter = $0 })) {
                Text("Show All").tag(GameFilter?.none)
                Divider()
                ForEach(GameFilter.allCases, id: \.self) { Text($0.title).tag(GameFilter?.some($0)) }
            }
            Divider()
            Button("Couch Mode") { if model.couchMode { model.leaveCouchMode() } else { model.enterCouchMode() } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Game") {
            Button("Play") { if let id = model.selectedGameID { model.play(id) } }
                .keyboardShortcut("p")
                .disabled(!menu.hasSelection || menu.isRunning)
            Button("Stop…") { model.confirmingStop = model.selectedGameID }
                .keyboardShortcut(".")
                .disabled(!menu.isRunning)
            Divider()
            Button("Show in Finder") { if let id = model.selectedGameID { model.showInFinder(id) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!menu.hasSelection)
            Button("Open Store Page") { if let id = model.selectedGameID { model.openStorePage(id) } }
                .disabled(!menu.hasStorePage)
            Button("Refresh Details") { if let id = model.selectedGameID { model.refreshDetails(id) } }
                .disabled(!menu.hasSelection)
            Divider()
            Button("Choose Cover…") { if let id = model.selectedGameID { GamePanels.chooseCover(model, id) } }
                .disabled(!menu.hasSelection)
            Button("Reset Cover") { if let id = model.selectedGameID { model.resetCover(id) } }
                .disabled(!menu.hasCustomCover)
            Divider()
            Button("Remove from Library") { if let id = model.selectedGameID { model.remove(id) } }
                .disabled(!menu.hasSelection)
        }
    }
}

/// Open panels shared by menus, buttons and context menus.
enum GamePanels {
    static func addGame(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add Game")
        panel.prompt = String(localized: "Add")
        panel.allowedContentTypes = [.application, UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { model.add(files: panel.urls) }
    }

    static func chooseCover(_ model: AppModel, _ id: String) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Cover")
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { model.chooseCover(id, image: url) }
    }

    static func locate(_ model: AppModel, _ id: String) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Locate Game")
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { model.locate(id, at: url) }
    }

    static func chooseSteamFolder(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Steam Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { Task { await model.useSteamFolder(url) } }
    }
}
