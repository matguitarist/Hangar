import Foundation

/// What a controller's buttons and sticks read at one moment (S-029). The app fills it from GameController.
public struct GamepadState: Sendable, Equatable {
    public var dpad: CouchDirection?
    /// The left stick, -1...1, up positive.
    public var stickX: Float = 0
    public var stickY: Float = 0
    public var a = false
    public var b = false
    public var y = false
    public var menu = false

    public init(dpad: CouchDirection? = nil, stickX: Float = 0, stickY: Float = 0, a: Bool = false, b: Bool = false, y: Bool = false, menu: Bool = false) {
        self.dpad = dpad
        self.stickX = stickX
        self.stickY = stickY
        self.a = a
        self.b = b
        self.y = y
        self.menu = menu
    }

    /// The direction held: the D-pad, else the stick past its dead zone along its stronger axis.
    public var direction: CouchDirection? {
        if let dpad { return dpad }
        let dead: Float = 0.5
        guard max(abs(stickX), abs(stickY)) >= dead else { return nil }
        if abs(stickX) >= abs(stickY) { return stickX > 0 ? .right : .left }
        return stickY > 0 ? .up : .down
    }
}

/// A press to act on, once per press: a held direction repeats after a pause, like a key.
public enum GamepadEvent: Sendable, Hashable {
    case move(CouchDirection)
    case a, b, y, menu
}

/// Turns states read over time into events: buttons fire when pressed (not while held),
/// a direction fires at once, then again after `delay` and every `interval` while held.
public struct GamepadMapper: Sendable {
    public var delay: TimeInterval = 0.4
    public var interval: TimeInterval = 0.12
    private var last = GamepadState()
    private var held: (direction: CouchDirection, next: Date)?

    public init() {}

    public mutating func step(_ state: GamepadState, now: Date) -> [GamepadEvent] {
        var events: [GamepadEvent] = []
        if let direction = state.direction {
            if held?.direction != direction {
                events.append(.move(direction))
                held = (direction, now.addingTimeInterval(delay))
            } else if let next = held?.next, now >= next {
                events.append(.move(direction))
                held = (direction, now.addingTimeInterval(interval))
            }
        } else {
            held = nil
        }
        if state.a && !last.a { events.append(.a) }
        if state.b && !last.b { events.append(.b) }
        if state.y && !last.y { events.append(.y) }
        if state.menu && !last.menu { events.append(.menu) }
        last = state
        return events
    }
}
