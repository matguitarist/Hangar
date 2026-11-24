import Foundation
import Testing
@testable import HangarKit

// S-029
@Test func theDpadAndTheLeftStickMoveTheSelection() {
    #expect(GamepadState(dpad: .left).direction == .left)
    #expect(GamepadState(stickX: 0.9, stickY: 0.2).direction == .right)
    #expect(GamepadState(stickX: -0.1, stickY: -0.8).direction == .down)
    #expect(GamepadState(stickX: 0.3, stickY: 0.3).direction == nil)
}

@Test func aHeldDirectionRepeatsAfterAPause() {
    var mapper = GamepadMapper()
    let start = Date(timeIntervalSince1970: 1000)
    #expect(mapper.step(GamepadState(dpad: .right), now: start) == [.move(.right)])
    #expect(mapper.step(GamepadState(dpad: .right), now: start.addingTimeInterval(0.2)) == [])
    #expect(mapper.step(GamepadState(dpad: .right), now: start.addingTimeInterval(0.41)) == [.move(.right)])
    #expect(mapper.step(GamepadState(dpad: .right), now: start.addingTimeInterval(0.45)) == [])
    #expect(mapper.step(GamepadState(dpad: .right), now: start.addingTimeInterval(0.54)) == [.move(.right)])
    #expect(mapper.step(GamepadState(), now: start.addingTimeInterval(0.6)) == [])
    #expect(mapper.step(GamepadState(dpad: .down), now: start.addingTimeInterval(0.61)) == [.move(.down)])
}

@Test func buttonsFireOncePerPress() {
    var mapper = GamepadMapper()
    let now = Date(timeIntervalSince1970: 1000)
    #expect(mapper.step(GamepadState(a: true), now: now) == [.a])
    #expect(mapper.step(GamepadState(a: true), now: now.addingTimeInterval(1)) == [])
    #expect(mapper.step(GamepadState(), now: now.addingTimeInterval(2)) == [])
    #expect(mapper.step(GamepadState(b: true, y: true, menu: true), now: now.addingTimeInterval(3)) == [.b, .y, .menu])
}
