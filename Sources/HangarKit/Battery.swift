import Foundation

/// Other settings for a game when the Mac runs on battery (S-025).
public struct BatteryProfile: Codable, Sendable, Hashable {
    /// Metal's performance HUD on battery, in place of the game's own choice.
    public var metalHUD = false
    /// Lower the display's resolution while the game runs, and put it back when it quits.
    public var lowerResolution = true
    /// Suggest Low Power Mode at launch when it's off (an app can't turn it on).
    public var suggestLowPowerMode = true

    public init(metalHUD: Bool = false, lowerResolution: Bool = true, suggestLowPowerMode: Bool = true) {
        self.metalHUD = metalHUD
        self.lowerResolution = lowerResolution
        self.suggestLowPowerMode = suggestLowPowerMode
    }

    enum CodingKeys: String, CodingKey { case metalHUD, lowerResolution, suggestLowPowerMode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        lowerResolution = try c.decodeIfPresent(Bool.self, forKey: .lowerResolution) ?? true
        suggestLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .suggestLowPowerMode) ?? true
    }
}

/// What powers the Mac at launch.
public enum PowerSource: String, Sendable {
    case ac, battery
}

extension GameOptions {
    /// The battery profile, when the game has one and the Mac is on battery.
    public func batteryProfile(on power: PowerSource) -> BatteryProfile? {
        power == .battery ? battery : nil
    }

    /// The options a launch uses: the battery profile's on battery, the game's own otherwise.
    public func forLaunch(on power: PowerSource) -> GameOptions {
        guard let profile = batteryProfile(on: power) else { return self }
        var options = self
        options.metalHUD = profile.metalHUD
        return options
    }
}

/// A display mode, as plain values: what CoreGraphics lists for a display.
public struct DisplayMode: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    var pixels: Int { pixelWidth * pixelHeight }
    var aspect: Double { Double(width) / Double(max(height, 1)) }
}

public enum DisplayModes {
    /// The mode to play in on battery: the same shape, at most four fifths of the pixels' width
    /// (the next "looks like" size down on a MacBook),
    /// the largest such mode, and the same refresh rate when there is one. Nil when there's none lower.
    public static func lower(than current: DisplayMode, among modes: [DisplayMode]) -> DisplayMode? {
        let limit = Double(current.pixelWidth) * 0.8
        let fitting = modes.filter { abs($0.aspect - current.aspect) < 0.02 && Double($0.pixelWidth) <= limit && $0.width >= 800 }
        let sameRate = fitting.filter { abs($0.refreshRate - current.refreshRate) < 1 }
        return (sameRate.isEmpty ? fitting : sameRate).max { ($0.pixels, $0.width) < ($1.pixels, $1.width) }
    }
}
