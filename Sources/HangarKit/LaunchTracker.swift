import Foundation

/// A game Hangar started, from the launch until its own process quits.
public struct LaunchState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case starting, running }
    public var phase: Phase = .starting
    public var launched: Date
    public var started: Date?
    public var pids: [pid_t] = []
    public var stoppedByUser = false
    /// Steam and Windows games take longer to appear: Steam or the bottle starts first.
    public var slowStart = false

    public init(phase: Phase = .starting, launched: Date, started: Date? = nil, pids: [pid_t] = [], slowStart: Bool = false) {
        self.phase = phase
        self.launched = launched
        self.started = started
        self.pids = pids
        self.slowStart = slowStart
    }
}

/// What a step of the tracker found.
public enum LaunchEvent: Sendable, Equatable {
    case started
    /// The game quit; quitRightAway when it ran under ten seconds and nobody stopped it.
    case finished(played: TimeInterval, quitRightAway: Bool)
    case didntStart
}

/// The rules that follow a launched game through the process list. The launch command
/// itself exits at once (open, CrossOver's wine), so running and playtime follow the
/// game's own process, found by its hints.
public enum LaunchTracker {
    public static let quickQuit: TimeInterval = 10

    public static func startTimeout(slow: Bool) -> TimeInterval { slow ? 120 : 30 }

    /// Launch Services gave a process id at once.
    public static func launched(_ state: inout LaunchState, pid: pid_t, now: Date) -> LaunchEvent? {
        guard state.phase == .starting else { return nil }
        state.phase = .running
        state.started = now
        state.pids = [pid]
        return .started
    }

    /// One look at the process list. Returns what changed, if anything; a finished or
    /// unstarted game is done and its state can be dropped.
    public static func step(_ state: inout LaunchState, hints: [String], processes: [RunningProcess], now: Date) -> LaunchEvent? {
        let alive = Set(processes.map(\.pid))
        let found = ProcessList.find(hints, in: processes).map(\.pid)
        let pids = Array(Set(found + state.pids.filter(alive.contains))).sorted()
        switch state.phase {
        case .starting:
            if !pids.isEmpty {
                state.phase = .running
                state.started = now
                state.pids = pids
                return .started
            }
            return now.timeIntervalSince(state.launched) > startTimeout(slow: state.slowStart) ? .didntStart : nil
        case .running:
            if pids.isEmpty {
                let played = now.timeIntervalSince(state.started ?? now)
                return .finished(played: played, quitRightAway: played < quickQuit && !state.stoppedByUser)
            }
            state.pids = pids
            return nil
        }
    }
}
