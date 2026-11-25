import AppTestKit
import Foundation
import HangarKit

/// M5 (Life on a Mac) checks, on the sample library.
extension SelfTest {
    static func lifeOnAMacChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        func find(_ title: String) -> Game? { model.library.games.first { $0.title == title } }

        // S-034: Vernal Edge's wiki notes say "Runs with D3DMetal. Set MSync on".
        if let vernal = find("Vernal Edge") {
            await model.loadCompatibility(vernal.id)
            await model.loadSaveLocations(vernal.id)
            let before = model.bottleSettings(for: vernal)
            let list = model.suggestions(for: vernal)
            check("S-034 the wiki's notes become suggestions", list.contains { $0.change == .graphics(.d3dMetal) } && list.allSatisfy { if case .wikiNote = $0.reason { true } else { false } },
                  "\(list.map(\.id)) from \(String(describing: before))")
            model.suggestionState[vernal.id] = nil
            model.applySuggestions(vernal.id)
            let game = model.game(vernal.id) ?? vernal
            check("S-034 Apply Suggestions changes the bottle", model.bottleSettings(for: game)?.graphics == .d3dMetal && model.suggestions(for: game).isEmpty)
            if case .applied = model.suggestionState[vernal.id] { check("S-034 and offers Undo", true) } else { check("S-034 and offers Undo", false) }
            model.undoSuggestions(vernal.id)
            check("S-034 Undo puts the settings back", model.bottleSettings(for: game) == before, String(describing: model.bottleSettings(for: game)))
            model.suggestionState[vernal.id] = nil
        }

        // S-025: Pocket Racer shows the HUD, but not on battery.
        if let moonlit = find("Pocket Racer") {
            let before = moonlit.options
            model.setOptions(moonlit.id) { $0.metalHUD = true }
            model.useBatteryProfile(moonlit.id, true)
            let game = model.game(moonlit.id) ?? moonlit
            Power.forced = .ac
            let plugged = try? model.launchPlan(for: game)
            check("S-025 plugged in, the game's own settings", plugged?.plan.environment["MTL_HUD_ENABLED"] == "1" && plugged?.battery == nil,
                  String(describing: Result { try model.launchPlan(for: game) }.map { ($0.plan.executable.path, $0.plan.environment) }))
            Power.forced = .battery
            Power.forcedLowPowerMode = false
            let unplugged = try? model.launchPlan(for: game)
            check("S-025 on battery, the battery settings", unplugged?.plan.environment["MTL_HUD_ENABLED"] == nil && unplugged?.battery != nil)
            if let profile = unplugged?.battery {
                model.notices[moonlit.id] = nil
                model.applyBatteryProfile(game, profile)
                check("S-025 the display is lowered while it plays", model.loweredDisplay.contains(moonlit.id))
                check("S-025 Low Power Mode is suggested when it's off", model.notices[moonlit.id] == .lowPowerModeOff)
                model.openedURLs = []
                model.openBatterySettings()
                check("S-025 Open Battery Settings opens System Settings", model.openedURLs.last?.scheme == "x-apple.systempreferences")
                model.restoreDisplay(after: moonlit.id)
                check("S-025 and put back when it quits", !model.loweredDisplay.contains(moonlit.id))
                model.notices[moonlit.id] = nil
                Power.forcedLowPowerMode = true
                model.applyBatteryProfile(game, profile)
                check("S-025 no reminder when Low Power Mode is on", model.notices[moonlit.id] == nil)
                model.restoreDisplay(after: moonlit.id)
            }
            model.useBatteryProfile(moonlit.id, false)
            check("S-025 turning it off forgets the battery settings", model.game(moonlit.id)?.options.battery == nil)
            model.setOptions(moonlit.id) { $0 = before }
            Power.forced = nil
            Power.forcedLowPowerMode = nil
        }
    }
}
