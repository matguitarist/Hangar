import AppKit
import Foundation
import HangarKit
import LogKit
import LogKitUI
import Observation
import SwiftUI

/// The sidebar pages.
enum SidebarItem: Hashable {
    case running, allGames, source(GameSource), bottle(String), collection(UUID), runners, log
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
        case .wine: "Wine"
        case .gamePortingToolkit: "Game Porting Toolkit"
        case .macRunner: "MacRunner"
        }
    }

    /// The store page, for Steam games.
    var storeURL: URL? { GameLinks.store(steamID: steamID) }
}


/// Something to say on a game's page after a launch.
enum GameNotice: Equatable {
    case didntStart(String)
    case quitRightAway
    /// A Windows game quit within a minute: why, from its Wine log, when a known line says (S-024).
    case crashed(CrashReason?)
    case didntCopy(String)
    /// After a game ran a while: did it work? (labels the snapshot taken at launch)
    case askWorked
    /// Launched on battery with Low Power Mode off, and the profile suggests it (S-025).
    case lowPowerModeOff
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
    /// CrossOver, Wine builds and Game Porting Toolkit on this Mac (the Runners page).
    var runners: [InstalledRunner] = []
    private(set) var isScanning = false
    private(set) var showsScanning = false
    private(set) var hasScanned = false

    // Browsing
    var selectedGameID: String? { didSet { syncMenu(); if selectedGameID != nil && selectedGameID != oldValue { showsGamePage = true } } }
    var showsGamePage = false
    var gamePageTab: GamePageTab = .overview
    /// Bumped when a game's settings change on disk, so the Settings tab reads them again.
    var settingsGeneration = 0
    /// The game whose bottle is being copied (S-011).
    var copyingBottle: String?
    var confirmingOwnBottle: String?
    let snapshots = SnapshotStore(folder: Store.snapshotsFolder)
    /// Known-good setups, read once from the manifest.
    @ObservationIgnored lazy var recipes: RecipeManifest = loadRecipes()
    /// Runners that updated, with the games that last worked on the old version.
    var runnerUpdates: [RunnerUpdateNotice] = []
    /// Snapshot mode only: open the game page scrolled to its end.
    var scrollGamePageToEnd = false
    /// The game whose setup is about to be shared (the confirmation is open).
    var sharingRecipe: String?
    /// In a test run, links and copies are recorded here instead of opening the browser or touching the clipboard.
    @ObservationIgnored var openedURLs: [URL] = []
    @ObservationIgnored var copiedText: String?
    /// The game whose recipe preview is open.
    var previewingRecipe: String?
    /// The snapshot taken before a recipe was applied, by game id: Undo restores it.
    var recipeUndo: [String: SettingsSnapshot] = [:]
    /// The snapshot taken when a game last started, by game id.
    var launchSnapshots: [String: SettingsSnapshot] = [:]
    /// The game whose Snapshots sheet is open.
    var showsSnapshots: String?
    /// The game whose Save Backups sheet is open (S-023).
    var showsBackups: String?
    /// Bumped when snapshots change, so lists read them again.
    var snapshotGeneration = 0
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
    let compatibilityCache = CompatibilityCache(folder: Store.compatibilityFolder, fetch: Store.compatibilityFetch,
                                                search: Store.compatibilitySearch)
    /// AppleGamingWiki's verdicts by game id: nil while loading, .some(nil) when the wiki has no page.
    var compatibility: [String: Compatibility?] = [:]
    let gameDataCache = GameDataCache(folder: Store.gameDataFolder, fetch: Store.gameDataFetch)
    /// Where each game saves, by game id: nil while loading, .some(nil) when PCGamingWiki has no page.
    var saveLocations: [String: [SaveLocation]?] = [:]
    /// The wiki page the save paths came from, by game id.
    var saveDataPages: [String: URL] = [:]
    /// Bumped when save backups change, so the Saves section and the Backups sheet read them again.
    var backupGeneration = 0
    /// Settings › Library: keep save backups in iCloud Drive. Turning it on or off moves them.
    var backupsInICloud: Bool = UserDefaults.standard.bool(forKey: "saves.iCloud") {
        didSet {
            guard backupsInICloud != oldValue else { return }
            if !Store.isOverridden { UserDefaults.standard.set(backupsInICloud, forKey: "saves.iCloud") }
            moveBackups(from: SaveBackupStore(root: Store.saveBackupsFolder(iCloud: oldValue)))
        }
    }
    let detailsCache: GameDetailsCache
    /// What each game is about (S-031), by game id: nil while loading, .some(nil) when nothing was found.
    var details: [String: GameDetails?] = [:]
    /// Games playing with the display lowered by their battery profile (S-025), and the mode to put back.
    var loweredDisplay: Set<String> = []
    @ObservationIgnored var displayRestore: (id: String, mode: CGDisplayMode)?
    /// The game on the Mac App Store, when AppleGamingWiki doesn't say it runs natively (S-033).
    var appStoreApps: [String: MacAppStore.App?] = [:]
    /// View › Fetch All Details: its progress, shown above the library until dismissed (S-032).
    var detailsRun: DetailsRun?
    @ObservationIgnored var detailsTask: Task<Void, Never>?
    /// The TheGamesDB API key (Settings › Library), kept in the Keychain.
    var theGamesDBKey: String = Keychain.read("thegamesdb") ?? "" {
        didSet {
            guard theGamesDBKey != oldValue else { return }
            let key = theGamesDBKey.trimmingCharacters(in: .whitespacesAndNewlines)
            Keychain.write("thegamesdb", key)
            Task {
                await detailsCache.setKey(key)
                // Games that had nothing without a key can have details now.
                details = details.filter { $0.value != nil }
            }
        }
    }
    /// Bumped when covers can change everywhere (a new SteamGridDB key), so tiles look again.
    var coverGeneration = 0
    /// The SteamGridDB API key (Settings › Library), kept in the Keychain.
    var steamGridDBKey: String = Keychain.read("steamgriddb") ?? "" {
        didSet {
            guard steamGridDBKey != oldValue else { return }
            Keychain.write("steamgriddb", steamGridDBKey.trimmingCharacters(in: .whitespacesAndNewlines))
            let key = steamGridDBKey
            Task { await covers.setGridKey(key); coverGeneration += 1 }
        }
    }
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
        covers = CoverCache(folder: Store.coversFolder, gridKey: Keychain.read("steamgriddb"))
        detailsCache = GameDetailsCache(folder: Store.detailsFolder, key: Keychain.read("thegamesdb"), fetch: Store.detailsFetch,
                                        steamSpacing: Store.isOverridden ? 0 : 1.5)
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
        runners = RunnerScanner.scan(roots)
        checkRunnerUpdates()
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
        case .allGames, .log, .runners: all = library.games
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
        case .runners: String(localized: "Runners")
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
        menu.isFetchingDetails = detailsTask != nil
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
