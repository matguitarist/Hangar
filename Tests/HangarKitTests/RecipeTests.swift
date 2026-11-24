import Foundation
import Testing
@testable import HangarKit

private let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/recipes.json")

// S-016
@Test func theManifestIsCheckedAndABadEntryIsSkipped() throws {
    let manifest = RecipeManifest.parse(try Data(contentsOf: manifestURL))
    #expect(manifest.recipes.map(\.id) == ["moonlit-harbor"])
    #expect(manifest.skipped.count == 5)
    #expect(manifest.skipped.contains { $0.hasPrefix("bad-hive") })
    #expect(manifest.skipped.contains { $0.hasPrefix("bad-copy") })
    #expect(RecipeManifest.parse(Data("nope".utf8)).recipes.isEmpty)
    #expect(RecipeManifest.parse(Data(#"{"schema": 99, "recipes": []}"#.utf8)).skipped.first?.contains("newer") == true)
}

@Test func aRecipeTurnsIntoAListOfChanges() throws {
    let recipe = try #require(RecipeManifest.parse(try Data(contentsOf: manifestURL)).recipes.first)
    let changes = recipe.changes
    #expect(changes.first == .graphics(.dxmt))
    #expect(changes.contains(.setting("MSync", true)))
    #expect(changes.contains(.variable("DXMT_LOG_LEVEL", "none")))
    #expect(changes.contains(.arguments("-windowed -skipintro")))
    #expect(changes.contains(.dllOverride("dinput8", "native,builtin")))
    #expect(changes.contains { if case .registry = $0 { true } else { false } })
    #expect(changes.last == .copy(.init(from: "@game/readme.txt", to: "@game/data/readme-copy.txt")))
}

@Test func applyingChangesTheBottleAndTheSnapshotPutsItBack() throws {
    let roots = try fixtureRoots()
    let bottle = roots.bottles.appending(path: "Classics")
    let recipe = try #require(RecipeManifest.parse(try Data(contentsOf: manifestURL)).recipes.first)
    // A Start menu shortcut: @game is the Program Files folder named like the game.
    let game = try #require(LibraryScanner.scanNow(roots).first { $0.title == "Moonlit Harbor" })
    #expect(recipe.matches(game))
    #expect(Recipe.gameFolder(game, bottle: bottle) == "drive_c/Program Files/Moonlit Harbor")
    try recipe.check(game: game, bottle: bottle)
    let store = SnapshotStore(folder: FileManager.default.temporaryDirectory.appending(path: "HangarRecipe-\(UUID().uuidString)"))
    let before = try ["cxbottle.conf", "user.reg", "system.reg"].map { try Data(contentsOf: bottle.appending(path: $0)) }
    let snapshot = try store.take(game, bottle: bottle, extraFiles: recipe.touchedFiles(game: game, bottle: bottle), reason: .recipe, detail: recipe.title)

    let options = try recipe.apply(to: game, bottle: bottle)
    #expect(BottleSettings.read(bottle: bottle).graphics == .dxmt)
    let user = try RegFile.read(bottle.appending(path: "user.reg"))
    #expect(user.string("dinput8", in: "Software\\Wine\\DllOverrides") == "native,builtin")
    #expect(user.value("Fullscreen", in: "Software\\Moonlit Harbor\\Settings") == "dword:00000000")
    let copy = bottle.appending(path: "drive_c/Program Files/Moonlit Harbor/data/readme-copy.txt")
    #expect(FileManager.default.fileExists(atPath: copy.path))
    #expect(options.arguments == "-windowed -skipintro" && options.variables.map(\.name) == ["DXMT_LOG_LEVEL"])

    let restored = try store.restore(snapshot, bottle: bottle)
    #expect(try ["cxbottle.conf", "user.reg", "system.reg"].map { try Data(contentsOf: bottle.appending(path: $0)) } == before)
    #expect(!FileManager.default.fileExists(atPath: copy.path))
    #expect(restored == game.options)
}

@Test func aRecipeWhoseFilesArentThereIsStoppedBeforeItStarts() throws {
    let roots = try fixtureRoots()
    let bottle = roots.bottles.appending(path: "Classics")
    var game = Game(id: "z", title: "Elsewhere", source: .crossOver, runner: .crossOver, exe: "C:\\Games\\Elsewhere\\e.lnk")
    game.startsShortcut = true
    var recipe = Recipe(id: "z", title: "Z", match: .init(title: "Elsewhere"))
    recipe.copies = [.init(from: "@game/a.dll", to: "@game/b.dll")]
    #expect(throws: RecipeError.noGameFolder) { try recipe.check(game: game, bottle: bottle) }
    game.options.exe = "C:\\Program Files\\Moonlit Harbor\\MoonlitHarbor.exe"
    #expect(Recipe.gameFolder(game, bottle: bottle) == "drive_c/Program Files/Moonlit Harbor")
    #expect(throws: RecipeError.missingFile("@game/a.dll")) { try recipe.check(game: game, bottle: bottle) }
    let before = try Data(contentsOf: bottle.appending(path: "cxbottle.conf"))
    recipe.graphics = .dxvk
    #expect(throws: RecipeError.self) { try recipe.apply(to: game, bottle: bottle) }
    #expect(try Data(contentsOf: bottle.appending(path: "cxbottle.conf")) == before)
}

@Test func recipesMatchBySteamIDExeOrTitle() {
    let steam = Game(id: "a", title: "Anything", source: .steam, steamID: "42")
    #expect(Recipe(id: "x", title: "x", match: .init(steamID: "42")).matches(steam))
    #expect(!Recipe(id: "x", title: "x", match: .init(steamID: "43", title: "Anything")).matches(steam))
    let program = Game(id: "b", title: "Harbor", source: .crossOver, runner: .crossOver, exe: "C:\\Games\\Harbor.exe")
    #expect(Recipe(id: "x", title: "x", match: .init(exe: "harbor.exe")).matches(program))
    #expect(Recipe(id: "x", title: "x", match: .init(title: "harbor")).matches(program))
}
