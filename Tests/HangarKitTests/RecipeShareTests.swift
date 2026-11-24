import Foundation
import Testing
@testable import HangarKit

// S-019
@Test func theSharedRecipeHoldsOnlySettingsNeverTheUsersPaths() throws {
    var game = Game(id: "x", title: "Moonlit Harbor: Deluxe", source: .crossOver, runner: .crossOver,
                    path: "/Users/mathilde/Library/Application Support/CrossOver/Bottles/Classics/drive_c/Program Files/Moonlit Harbor/MoonlitHarbor.exe",
                    exe: "C:\\Program Files\\Moonlit Harbor\\MoonlitHarbor.exe", bottle: "Classics")
    game.options.variables = [EnvironmentVariable(name: "DXMT_LOG_LEVEL", value: "none"),
                              EnvironmentVariable(name: "DXVK_LOG_PATH", value: "/Users/mathilde/Desktop"),
                              EnvironmentVariable(name: "SAVE_DIR", value: "C:\\users\\crossover\\Saved")]
    game.options.arguments = "-windowed -name 'Big Map' -log /Users/mathilde/log.txt -profile mathilde"
    let settings = BottleSettings(graphics: .dxmt, msync: true)
    let recipe = RecipeShare.recipe(for: game, settings: settings, runner: "CrossOver 26.3", userName: "mathilde", home: "/Users/mathilde")
    let json = RecipeShare.json(recipe)

    #expect(recipe.id == "moonlit-harbor-deluxe")
    #expect(recipe.match.exe == "MoonlitHarbor.exe" && recipe.match.title == "Moonlit Harbor: Deluxe")
    #expect(recipe.graphics == .dxmt && recipe.msync == true && recipe.highResolution == false)
    #expect(recipe.env == ["DXMT_LOG_LEVEL": "none"])
    #expect(recipe.arguments == "-windowed -name 'Big Map' -log -profile")
    #expect(recipe.tested == "CrossOver 26.3")
    #expect(!json.contains("/Users/") && !json.lowercased().contains("mathilde") && !json.lowercased().contains("users"))
    #expect(!json.contains("Bottles") && !json.contains("Classics"))
    // It reads back as a valid manifest entry.
    let manifest = RecipeManifest.parse(Data("{\"schema\": 1, \"recipes\": [\(json)]}".utf8))
    #expect(manifest.recipes.first == recipe && manifest.skipped.isEmpty)
}

@Test func theIssueURLCarriesTheJSONInItsBody() throws {
    var recipe = Recipe(id: "a-b", title: "A+B", match: .init(steamID: "123"))
    recipe.graphics = .dxvk
    let url = RecipeShare.issueURL(recipe)
    #expect(url.absoluteString.hasPrefix("https://github.com/matguitarist/Hangar/issues/new?"))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first { $0.name == "title" }?.value == "Recipe: A+B")
    let body = try #require(items.first { $0.name == "body" }?.value)
    #expect(body.contains("\u{60}\u{60}\u{60}json") && body.contains(RecipeShare.json(recipe)))
    #expect(!url.absoluteString.contains("+B"))
}
