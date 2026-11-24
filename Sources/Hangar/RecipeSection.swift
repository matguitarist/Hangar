import HangarKit
import SwiftUI

/// "Recommended Setup" on a game's page: what the recipe is, and Review or Undo.
struct RecipeSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        if let recipe = model.recipe(for: game) {
            Section {
                if let notes = recipe.notes, !notes.isEmpty {
                    Text(notes)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tested = recipe.tested {
                    LabeledContent("Tested with", value: tested)
                }
                if model.recipeUndo[game.id] != nil {
                    HStack(spacing: Space.sm) {
                        Label("Applied", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo") { model.undoRecipe(game.id) }
                            .help(String(localized: "Put back the settings and files the recipe changed"))
                            .disabled(game.bottle.map(model.bottleIsBusy) == true)
                    }
                } else {
                    Button("Review Changes…") { model.previewingRecipe = game.id }
                        .help(String(localized: "See what the recommended setup changes before applying it"))
                }
            } header: {
                Text("Recommended Setup")
            }
        }
    }
}

/// The changes a recipe makes, before applying it.
struct RecipeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let gameID: String

    var body: some View {
        let game = model.game(gameID)
        let recipe = game.flatMap(model.recipe)
        let problem = game.flatMap { g in recipe.flatMap { model.recipeProblem($0, game: g) } }
        let mates = game.map(model.bottleMates) ?? []
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Apply the Recommended Setup to \(game?.title ?? "")?")
                .font(.headline)
            Text("Hangar saves a snapshot first, so Undo puts everything back.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(Array((recipe?.changes ?? []).enumerated()), id: \.offset) { _, change in
                Text(change.text)
                    .lineLimit(2)
                    .help(change.text)
            }
            .listStyle(.bordered)
            .frame(height: min(260, CGFloat(max(recipe?.changes.count ?? 0, 1)) * 23 + 8))
            if !mates.isEmpty, let bottle = game?.bottle {
                Label(mates.count == 1
                      ? String(localized: "The bottle \(bottle) also holds \(mates[0].title): it gets these settings too.")
                      : String(localized: "The bottle \(bottle) also holds \(mates.count) other games: they get these settings too."),
                      systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply Setup") {
                    model.applyRecipe(gameID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recipe == nil || problem != nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .noInitialFocus()
    }
}
