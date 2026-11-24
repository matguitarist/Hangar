import CoreGraphics
import Foundation
import HangarKit

/// Battery profiles (S-025): other settings for a game when the Mac is unplugged at launch.
extension AppModel {
    /// The launch plan for a game with the settings for this power source, and its battery profile when it applies.
    func launchPlan(for game: Game) throws(LaunchError) -> (plan: LaunchPlan, battery: BatteryProfile?) {
        let power = Power.source
        var launching = game
        launching.options = game.options.forLaunch(on: power)
        return (try LaunchPlanner.plan(for: launching, roots: roots), game.options.batteryProfile(on: power))
    }

    /// What the profile does besides the launch's own settings: the display, and Low Power Mode.
    func applyBatteryProfile(_ game: Game, _ profile: BatteryProfile) {
        log.post(.info, "On battery: \(game.title) starts with its battery settings", source: "Battery")
        if profile.lowerResolution {
            if Store.isOverridden {
                loweredDisplay.insert(game.id)
            } else if displayRestore == nil, let change = DisplayResolution.lower() {
                displayRestore = (game.id, change.original)
                loweredDisplay.insert(game.id)
                log.post(.info, "Lowered the display to \(change.now.width) × \(change.now.height) while \(game.title) runs", source: "Battery")
            }
        }
        if profile.suggestLowPowerMode, !Power.lowPowerMode {
            notices[game.id] = .lowPowerModeOff
        }
    }

    /// When the game quits: the display as it was.
    func restoreDisplay(after id: String) {
        loweredDisplay.remove(id)
        guard let restore = displayRestore, restore.id == id else { return }
        DisplayResolution.restore(restore.mode)
        displayRestore = nil
        log.post(.info, "Put the display back to \(restore.mode.width) × \(restore.mode.height)", source: "Battery")
    }

    /// Settings tab › On Battery: turning it off forgets the battery settings.
    func useBatteryProfile(_ id: String, _ on: Bool) {
        setOptions(id) { $0.battery = on ? ($0.battery ?? BatteryProfile()) : nil }
    }

    func openBatterySettings() {
        open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }
}
