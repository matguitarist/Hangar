import AppKit
import Foundation
import HangarKit
import LogKit
import LogKitUI
import Observation
import SwiftUI

/// The sidebar pages.
enum SidebarItem: Hashable {
    case running, allGames, source(GameSource), bottle(String), collection(UUID), log
}

extension GameSource {
    /// The sidebar name of a source.
    var title: String {
        switch self {
        case .steam: "Steam"
        case .crossOver: "CrossOver"
        case .macApp: String(localized: "Mac Apps")
        case .addedByHand: String(localized: "Added by You")
        }
    }

    var symbol: String {
        switch self {
        case .steam: "cloud"
        case .crossOver: "wineglass"
        case .macApp: "macwindow"
        case .addedByHand: "plus.square.on.square"
        }
    }
}

extension Game {
    /// Where the game came from, as a tile shows it: "Steam", "CrossOver · Steam".
    var sourceLabel: String {
        switch source {
        case .steam: "Steam"
        case .crossOver: steamID == nil ? "CrossOver" : "CrossOver · Steam"
        case .macApp: String(localized: "Mac App")
        case .addedByHand: String(localized: "Added by You")
        }
    }

    var runnerLabel: String {
        switch runner {
        case .native: "Mac"
        case .crossOver: bottle.map { String(localized: "CrossOver, bottle \($0)") } ?? "CrossOver"
        }
    }

    /// The store page, for Steam games.
    var storeURL: URL? { steamID.flatMap { URL(string: "https://store.steampowered.com/app/\($0)/") } }
}


/// Something to say on a game's page after a launch.
enum GameNotice: Equatable {
    case didntStart(String)
    case quitRightAway
}

/// A file dropped or chosen that needs the "Add Windows Game" sheet.
struct AddRequest: Identifiable, Equatable {
    let id = UUID()
    let file: URL
    var isWindowsProgram: Bool { LibraryModel.isWindowsProgram(file) }
}

/// What the window shows. Data logic lives in HangarKit.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .allGames
    let log = Store.log
    let logViewer: LogViewerModel

    // The library
    var library = LibraryFile() { didSet { if library != oldValue { scheduleSave() } } }
    private(set) var roots: LibraryRoots
    private(set) var notes: [ScanNote] = []
    private(set) var bottles: [String] = []
    private(set) var signedOutBottles: Set<String> = []
    private(set) var isScanning = false
    private(set) var showsScanning = false
    private(set) var hasScanned = false

    // Browsing
    var selectedGameID: String? { didSet { syncMenu(); if selectedGameID != nil && selectedGameID != oldValue { showsGamePage = true } } }
    var showsGamePage = false
    var searchText = ""
    var focusSearch = 0
    var sort: GameSort = GameSort(rawValue: UserDefaults.standard.string(forKey: "library.sort") ?? "") ?? .name {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(sort.rawValue, forKey: "library.sort") }; syncMenu() }
    }
    var renamingCollection: UUID?
    var addRequest: AddRequest?
    var confirmingStop: String?

    // Launching
    var running: [String: LaunchState] = [:] { didSet { syncMenu() } }
    var notices: [String: GameNotice] = [:]
    let covers: CoverCache
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored var monitor: Task<Void, Never>?

    /// The app's own language. Changing it takes effect after a restart.
    var language: AppLanguage = AppLanguage.current {
        didSet { if language != oldValue { language.apply() } }
    }

    var checksForUpdates: Bool = Updater.shared.automaticallyChecks {
        didSet { if Updater.shared.isAvailable { Updater.shared.automaticallyChecks = checksForUpdates } }
    }

    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init() {
        logViewer = LogViewerModel(store: Store.log)
        covers = CoverCache(folder: Store.coversFolder)
        let saved = LibraryFile.load(from: Store.url)
        roots = Store.roots(steamFolder: saved.steamFolder)
        library = saved
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log.post(.info, "Hangar \(version) started", source: "App")
        syncMenu()
    }

    // MARK: Scanning

    /// Scans every source again (View › Refresh Library). Cached games show meanwhile.
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        let reveal = Task { try? await Task.sleep(for: .milliseconds(500)); if isScanning { showsScanning = true } }
        let roots = self.roots
        let result = await LibraryScanner.scan(roots)
        reveal.cancel()
        withAnimation(.default) {
            library.merge(scanned: result.games, unreachable: result.unreachable)
        }
        notes = result.notes
        bottles = result.bottles
        signedOutBottles = Set(result.bottles.filter { name in
            let steam = CrossOverScanner.steamFolder(bottle: roots.bottles.appending(path: name))
            return FileManager.default.fileExists(atPath: steam.path) && !SteamScanner.isSignedIn(steamRoot: steam)
        })
        for note in result.notes {
            switch note {
            case let .libraryMissing(path): log.post(.warning, "The Steam library at \(path) isn't connected", source: "Library")
            case let .bottleUnreadable(name): log.post(.warning, "Can't read the bottle \(name)", source: "Library")
            }
        }
        log.post(.info, "Found \(result.games.count) games", source: "Library")
        isScanning = false
        showsScanning = false
        hasScanned = true
        if let id = selectedGameID, game(id) == nil { selectedGameID = nil }
        syncMenu()
    }

    /// Choose Steam Folder… on the empty page: Steam somewhere other than ~/Library/Application Support/Steam.
    func useSteamFolder(_ url: URL) async {
        library.steamFolder = url.path
        roots = Store.roots(steamFolder: url.path)
        await refresh()
    }

    // MARK: What the pages show

    func game(_ id: String?) -> Game? {
        guard let id else { return nil }
        return library.games.first { $0.id == id }
    }

    var selectedGame: Game? { game(selectedGameID) }

    /// The games of a sidebar page, searched and sorted.
    func games(for item: SidebarItem) -> [Game] {
        let all: [Game]
        switch item {
        case .allGames, .log: all = library.games
        case .running: all = library.games.filter { running[$0.id] != nil }
        case let .source(source): all = library.games.filter { $0.source == source }
        case let .bottle(name): all = library.games.filter { $0.bottle == name && $0.source == .crossOver }
        case let .collection(id):
            let ids = library.collections.first { $0.id == id }?.gameIDs ?? []
            all = library.games.filter { ids.contains($0.id) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return sort.sorted(query.isEmpty ? all : all.filter { GameSearch.matches(query, title: $0.title) })
    }

    func pageTitle(_ item: SidebarItem) -> String {
        switch item {
        case .running: String(localized: "Running")
        case .allGames: String(localized: "All Games")
        case let .source(source): source.title
        case let .bottle(name): name
        case let .collection(id): library.collections.first { $0.id == id }?.name ?? ""
        case .log: String(localized: "Log")
        }
    }

    /// The Steam row's message when a library folder isn't connected.
    var steamNote: String? {
        for note in notes {
            if case let .libraryMissing(path) = note {
                let parts = path.split(separator: "/")
                let drive = parts.count > 1 && parts[0] == "Volumes" ? String(parts[1]) : (parts.last.map(String.init) ?? path)
                return String(localized: "The library on \(drive) isn't connected. Its games come back when the drive is.")
            }
        }
        return nil
    }

    func bottleNote(_ name: String) -> String? {
        notes.contains(.bottleUnreadable(name: name))
            ? String(localized: "Hangar can't read the bottle \(name). Open it once in CrossOver, then refresh.") : nil
    }

    func needsSteamSignIn(_ game: Game) -> Bool {
        game.steamID != nil && game.bottle.map(signedOutBottles.contains) == true
    }

    func filesMissing(_ game: Game) -> Bool {
        !game.path.isEmpty && !FileManager.default.fileExists(atPath: game.path)
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        do { try library.save(to: Store.url) } catch { log.post(.error, "Can't save the library: \(error.localizedDescription)", source: "Library") }
    }

    // MARK: Menus

    func syncMenu() {
        let menu = MenuState.shared
        let game = selectedGame
        menu.hasSelection = game != nil
        menu.isRunning = game.map { running[$0.id] != nil } ?? false
        menu.hasStorePage = game?.storeURL != nil
        menu.hasCustomCover = game?.customCover != nil
        menu.sort = sort
    }
}

/// Library rules the app needs outside the model.
enum LibraryModel {
    /// A Windows program: an .exe that starts with the "MZ" header.
    static func isWindowsProgram(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "exe", let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data("MZ".utf8)
    }
}
