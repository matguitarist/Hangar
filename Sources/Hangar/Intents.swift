import AppIntents
import Foundation
import HangarKit

// Shortcuts actions (S-027). On a Mac, people find each AppIntent in the Shortcuts app and in
// Spotlight; App Shortcuts phrases aren't supported, so there are none. build.sh extracts the
// metadata (Metadata.appintents) that makes them show up.

/// A game in the library, as Shortcuts sees it.
nonisolated struct GameEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Game"))
    static let defaultQuery = GameQuery()

    let id: String
    let title: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(detail)")
    }

    @MainActor init(_ game: Game) {
        id = game.id
        title = game.title
        detail = game.sourceLabel
    }
}

/// Finds games by id, or by name with the library's own search ("bg3").
nonisolated struct GameQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GameEntity] {
        let model = try IntentModel.current()
        return identifiers.compactMap { model.game($0) }.map(GameEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GameEntity] {
        try IntentModel.current().library.games
            .filter { GameSearch.matches(string, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(GameEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GameEntity] {
        try IntentModel.current().library.games
            .sorted { ($0.lastPlayed ?? .distantPast, $1.title) > ($1.lastPlayed ?? .distantPast, $0.title) }
            .map(GameEntity.init)
    }
}

/// The app's model, for intents that run in Hangar's own process.
@MainActor
enum IntentModel {
    static weak var model: AppModel?

    static func current() throws -> AppModel {
        guard let model else { throw IntentError.notReady }
        return model
    }
}

nonisolated enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case gameMissing
    case didntStart(String)
    case notRunning(String)
    case noSaves(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "Hangar is still opening. Try again in a moment."
        case .gameMissing: "That game isn't in the library anymore."
        case let .didntStart(reason): "\(reason)"
        case let .notRunning(title): "\(title) isn't running."
        case let .noSaves(title): "Hangar doesn't know where \(title) keeps its saves."
        }
    }
}

struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Game"
    static let description = IntentDescription("Starts a game from your Hangar library through its runner.")
    static let openAppWhenRun = false

    @Parameter(title: "Game") var game: GameEntity

    init() {}
    init(game: GameEntity) { self.game = game }

    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$game)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentModel.current()
        guard let entry = model.game(game.id) else { throw IntentError.gameMissing }
        model.play(entry.id)
        if case let .didntStart(reason) = model.notices[entry.id] {
            throw IntentError.didntStart(String(localized: "\(entry.title) didn't start. \(reason)"))
        }
        return .result(dialog: "Starting \(entry.title).")
    }
}

struct StopGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Game"
    static let description = IntentDescription("Quits a game Hangar started. Unsaved progress in the game is lost.")
    static let openAppWhenRun = false

    @Parameter(title: "Game") var game: GameEntity

    init() {}
    init(game: GameEntity) { self.game = game }

    static var parameterSummary: some ParameterSummary { Summary("Stop \(\.$game)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentModel.current()
        guard let entry = model.game(game.id) else { throw IntentError.gameMissing }
        guard model.running[entry.id] != nil else { throw IntentError.notRunning(entry.title) }
        model.stop(entry.id)
        return .result(dialog: "Stopping \(entry.title).")
    }
}

struct RunningGamesIntent: AppIntent {
    static let title: LocalizedStringResource = "Running Games"
    static let description = IntentDescription("The games Hangar started that are still running.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GameEntity]> {
        let model = try IntentModel.current()
        let games = model.library.games.filter { model.running[$0.id] != nil }
        return .result(value: games.map(GameEntity.init))
    }
}

struct BackUpSavesIntent: AppIntent {
    static let title: LocalizedStringResource = "Back Up Saves"
    static let description = IntentDescription("Copies a game's saves to Hangar's save backups now.")
    static let openAppWhenRun = false

    @Parameter(title: "Game") var game: GameEntity

    init() {}
    init(game: GameEntity) { self.game = game }

    static var parameterSummary: some ParameterSummary { Summary("Back up the saves of \(\.$game)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentModel.current()
        guard let entry = model.game(game.id) else { throw IntentError.gameMissing }
        if await model.backUpSaves(entry.id, reason: .byHand) != nil {
            return .result(dialog: "Backed up the saves of \(entry.title).")
        }
        // Nothing copied: the saves are unchanged since the last backup, or unknown.
        let known = model.knownSaveLocations(entry.id).contains { $0.kind == .saves && !$0.found.isEmpty }
        guard known else { throw IntentError.noSaves(entry.title) }
        return .result(dialog: "The saves of \(entry.title) haven't changed since the last backup.")
    }
}
