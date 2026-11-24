import Foundation
import HangarKit

/// Recipes: the known-good setup for a game, previewed, applied after a snapshot, and undone.
extension AppModel {
    func loadRecipes() -> RecipeManifest {
        guard let url = Store.recipesURL, let data = try? Data(contentsOf: url) else { return RecipeManifest() }
        let manifest = RecipeManifest.parse(data)
        for problem in manifest.skipped {
            log.post(.warning, "Skipped a recipe: \(problem)", source: "Recipes")
        }
        return manifest
    }

    /// The recipe for a game Hangar can set up: a CrossOver game in a bottle.
    func recipe(for game: Game) -> Recipe? {
        guard game.runner == .crossOver, game.bottle != nil else { return nil }
        return recipes.recipe(for: game)
    }

    /// Why the recipe can't be applied now, or nil.
    func recipeProblem(_ recipe: Recipe, game: Game) -> String? {
        guard let bottle = game.bottle else { return nil }
        if bottleIsBusy(bottle) { return String(localized: "Quit the games in the bottle \(bottle) first.") }
        do {
            try recipe.check(game: game, bottle: bottleURL(bottle))
        } catch {
            switch error {
            case .noGameFolder:
                return String(localized: "Hangar can't find the game's folder in its bottle. Choose its program in Settings › Launch Options, then try again.")
            case let .missingFile(path):
                return String(localized: "The recipe needs \(path), which isn't in the bottle.")
            }
        }
        return nil
    }

    /// Saves a snapshot, then writes the recipe into the game's bottle.
    func applyRecipe(_ id: String) {
        guard let game = game(id), let recipe = recipe(for: game), let name = game.bottle,
              recipeProblem(recipe, game: game) == nil else { return }
        let bottle = bottleURL(name)
        guard let snapshot = takeSnapshot(id, reason: .recipe, extraFiles: recipe.touchedFiles(game: game, bottle: bottle), detail: recipe.title) else { return }
        do {
            let options = try recipe.apply(to: game, bottle: bottle)
            setOptions(id) { $0 = options }
            recipeUndo[id] = snapshot
            log.post(.info, "Applied the recipe \(recipe.id) to \(game.title) in the bottle \(name)", source: "Recipes")
        } catch {
            // Put back whatever was written before the failure.
            _ = try? snapshots.restore(snapshot, bottle: bottle)
            log.post(.error, "Can't apply the recipe \(recipe.id) to \(game.title): \(error.localizedDescription)", source: "Recipes")
        }
        settingsGeneration += 1
    }

    /// Puts back every file the recipe changed, and the game's options.
    func undoRecipe(_ id: String) {
        guard let snapshot = recipeUndo[id] else { return }
        restore(snapshot)
        recipeUndo[id] = nil
    }
}
