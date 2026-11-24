import AppKit
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
        var plan = try LaunchPlanner.plan(for: launching, roots: roots)
        // A frame cap reaches DXVK games only (S-038).
        plan.environment.merge(frameCapEnvironment(game, cap: launching.options.frameCap)) { $1 }
        return (plan, game.options.batteryProfile(on: power))
    }

    /// DXVK_FRAME_RATE for a capped DXVK game, else nothing.
    func frameCapEnvironment(_ game: Game, cap: Int?) -> [String: String] {
        FrameCap.environment(cap: cap, backend: frameCapBackend(game), displayRate: NSScreen.main?.maximumFramesPerSecond ?? 60)
    }

    /// The graphics backend a frame cap depends on: the bottle's, for a CrossOver game run in its bottle.
    func frameCapBackend(_ game: Game) -> GraphicsBackend? {
        guard game.runner == .crossOver, game.options.runner == nil else { return nil }
        return bottleSettings(for: game)?.graphics
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
