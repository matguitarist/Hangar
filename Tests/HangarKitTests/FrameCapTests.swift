import Foundation
import Testing
@testable import HangarKit

// S-038
@Test func aFrameCapReachesDXVKGamesOnly() {
    #expect(FrameCap.environment(cap: 40, backend: .dxvk, displayRate: 120) == ["DXVK_FRAME_RATE": "40"])
    #expect(FrameCap.environment(cap: 0, backend: .dxvk, displayRate: 120) == ["DXVK_FRAME_RATE": "120"])
    #expect(FrameCap.environment(cap: 40, backend: .d3dMetal, displayRate: 120).isEmpty)
    #expect(FrameCap.environment(cap: nil, backend: .dxvk, displayRate: 120).isEmpty)
    #expect(FrameCap.environment(cap: 60, backend: nil, displayRate: 120).isEmpty)
}

@Test func theBatteryProfileCanHaveItsOwnCap() {
    var options = GameOptions()
    options.frameCap = 60
    options.battery = BatteryProfile()
    #expect(options.forLaunch(on: .battery).frameCap == 60)
    options.battery?.frameCap = 30
    #expect(options.forLaunch(on: .battery).frameCap == 30)
    #expect(options.forLaunch(on: .ac).frameCap == 60)
}

@Test func olderOptionsOpenWithoutACap() throws {
    let options = try JSONDecoder().decode(GameOptions.self, from: Data(#"{"metalHUD":true}"#.utf8))
    #expect(options.frameCap == nil)
}
