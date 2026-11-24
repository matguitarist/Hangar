import AppKit
import GameController
import HangarKit
import Observation

/// Game controllers (S-029): an Xbox, PlayStation or Switch pad drives couch mode while Hangar is in front.
/// Reads the pad 60 times a second only while one is connected and Hangar is the active app.
@Observable
final class ControllerCenter {
    /// The connected pad's name ("DualSense Wireless Controller"), or nil.
    private(set) var name: String?
    /// The SF Symbols the pad itself uses for A, B and Y (a cross, a circle and a triangle on a DualSense).
    private(set) var glyphs: [GamepadEvent: String] = [:]
    /// "Controller connected", shown for a moment.
    private(set) var justConnected = false

    @ObservationIgnored private var mapper = GamepadMapper()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onEvent: (GamepadEvent) -> Void = { _ in }

    func start() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.connected(announce: true) }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.connected(announce: false) }
            },
        ]
        GCController.startWirelessControllerDiscovery {}
        connected(announce: false)
    }

    private var pad: GCExtendedGamepad? {
        GCController.current?.extendedGamepad ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
    }

    private func connected(announce: Bool) {
        guard let pad else {
            name = nil
            glyphs = [:]
            timer?.invalidate()
            timer = nil
            return
        }
        name = pad.controller?.vendorName ?? String(localized: "Controller")
        glyphs = [.a: pad.buttonA.sfSymbolsName, .b: pad.buttonB.sfSymbolsName, .y: pad.buttonY.sfSymbolsName]
            .compactMapValues { $0 }
        if announce {
            justConnected = true
            Store.log.post(.info, "Controller connected: \(name ?? "")", source: "Couch")
            Task { try? await Task.sleep(for: .seconds(2.5)); justConnected = false }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
    }

    private func poll() {
        guard NSApp.isActive, let pad else { return }
        var state = GamepadState(stickX: pad.leftThumbstick.xAxis.value, stickY: pad.leftThumbstick.yAxis.value,
                                 a: pad.buttonA.isPressed, b: pad.buttonB.isPressed, y: pad.buttonY.isPressed,
                                 menu: pad.buttonMenu.isPressed || pad.buttonHome?.isPressed == true)
        if pad.dpad.left.isPressed { state.dpad = .left }
        else if pad.dpad.right.isPressed { state.dpad = .right }
        else if pad.dpad.up.isPressed { state.dpad = .up }
        else if pad.dpad.down.isPressed { state.dpad = .down }
        for event in mapper.step(state, now: Date()) { onEvent(event) }
    }
}

extension AppModel {
    /// A controller's press, as couch mode reads it. The self-test sends these too.
    func gamepad(_ event: GamepadEvent) {
        switch event {
        case let .move(direction): couch(.move(direction))
        case .a: couch(.play)
        case .b: couch(.back)
        case .y: couch(.details)
        case .menu: couch(.menu)
        }
    }
}
