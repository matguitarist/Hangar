import Foundation
import Testing
@testable import HangarKit

// S-025
@Test func thePowerSourcePicksTheProfileAtLaunch() throws {
    var options = GameOptions(metalHUD: true)
    #expect(options.forLaunch(on: .battery).metalHUD, "no profile: the same settings on battery")
    options.battery = BatteryProfile(metalHUD: false)
    #expect(options.forLaunch(on: .battery).metalHUD == false)
    #expect(options.forLaunch(on: .battery).environment["MTL_HUD_ENABLED"] == nil)
    #expect(options.forLaunch(on: .ac).metalHUD)
    #expect(options.batteryProfile(on: .ac) == nil)
    #expect(options.batteryProfile(on: .battery)?.lowerResolution == true)
}

@Test func optionsSavedBeforeBatteryProfilesStillOpen() throws {
    let old = try JSONDecoder().decode(GameOptions.self, from: Data(#"{"metalHUD":true,"arguments":"","variables":[]}"#.utf8))
    #expect(old.battery == nil && old.metalHUD)
    var options = GameOptions()
    options.battery = BatteryProfile(metalHUD: true, lowerResolution: false, suggestLowPowerMode: false)
    let back = try JSONDecoder().decode(GameOptions.self, from: JSONEncoder().encode(options))
    #expect(back.battery == options.battery)
    let partial = try JSONDecoder().decode(BatteryProfile.self, from: Data("{}".utf8))
    #expect(partial == BatteryProfile())
}

@Test func theLowerModeKeepsTheShapeAndRefreshRate() {
    // A 14-inch MacBook Pro: 1512×982 points at 2×, 120 Hz.
    let current = DisplayMode(width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
    let modes = [
        current,
        DisplayMode(width: 1512, height: 982, pixelWidth: 1512, pixelHeight: 982, refreshRate: 120),
        DisplayMode(width: 1147, height: 745, pixelWidth: 2294, pixelHeight: 1490, refreshRate: 120),
        DisplayMode(width: 1147, height: 745, pixelWidth: 2294, pixelHeight: 1490, refreshRate: 60),
        DisplayMode(width: 1024, height: 665, pixelWidth: 2048, pixelHeight: 1330, refreshRate: 120),
        DisplayMode(width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 120),  // 16:9, another shape
        DisplayMode(width: 640, height: 416, pixelWidth: 1280, pixelHeight: 832, refreshRate: 120),    // too small to play
    ]
    #expect(DisplayModes.lower(than: current, among: modes) == modes[2])
    #expect(DisplayModes.lower(than: modes[6], among: modes) == nil)
}
