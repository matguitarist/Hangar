import CoreGraphics
import Foundation
import HangarKit
import IOKit.ps

/// The Mac's power, for battery profiles (S-025). The self-test and snapshots set `forced`.
@MainActor
enum Power {
    static var forced: PowerSource?
    static var forcedLowPowerMode: Bool?

    /// Whether this Mac has a battery at all; a Mac without one doesn't show battery settings.
    static var hasBattery: Bool {
        if forced != nil || Store.isOverridden { return true }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return !list.isEmpty
    }

    static var source: PowerSource {
        if let forced { return forced }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return .ac }
        return (type as String) == "Battery Power" ? .battery : .ac
    }

    static var lowPowerMode: Bool {
        forcedLowPowerMode ?? ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// The main display's resolution, lowered while a game plays on battery. The change is for Hangar's
/// lifetime only (.forAppOnly): macOS puts the resolution back even if Hangar quits or crashes.
@MainActor
enum DisplayResolution {
    static func plain(_ m: CGDisplayMode) -> DisplayMode {
        DisplayMode(width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight, refreshRate: m.refreshRate)
    }

    /// Lowers it, and gives the mode to put back; nil when there's no lower mode or it didn't change.
    static func lower() -> (original: CGDisplayMode, now: DisplayMode)? {
        let display = CGMainDisplayID()
        guard let current = CGDisplayCopyDisplayMode(display) else { return nil }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
        guard let target = DisplayModes.lower(than: plain(current), among: modes.map(plain)),
              let mode = modes.first(where: { plain($0) == target }), set(mode, on: display) else { return nil }
        return (current, target)
    }

    static func restore(_ mode: CGDisplayMode) {
        _ = set(mode, on: CGMainDisplayID())
    }

    private static func set(_ mode: CGDisplayMode, on display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        return CGCompleteDisplayConfiguration(config, .forAppOnly) == .success
    }
}
