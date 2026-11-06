import Foundation

/// The demo session is a small state machine of its own because the simulated
/// clock, playback task and source ownership are demo-specific. It never drives
/// the dashboard directly: the dashboard continues to read `TripSession.state`.
/// The phase only advances after the matching trip transition succeeded.
enum DemoSessionPhase: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case stopped
}

struct DemoSessionState: Equatable, Sendable {
    private(set) var phase: DemoSessionPhase = .idle

    var hasSession: Bool { phase != .idle }
    var isRunning: Bool { phase == .running }
    var isPaused: Bool { phase == .paused || phase == .stopped }
    var isStopped: Bool { phase == .stopped }

    mutating func begin() -> Bool {
        guard phase == .idle else { return false }
        phase = .running
        return true
    }

    mutating func pause() -> Bool {
        guard phase == .running else { return false }
        phase = .paused
        return true
    }

    mutating func stop() -> Bool {
        guard phase == .running || phase == .paused else { return false }
        phase = .stopped
        return true
    }

    mutating func resume() -> Bool {
        guard phase == .paused || phase == .stopped else { return false }
        phase = .running
        return true
    }

    mutating func reset() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }
}

/// Every playback loop gets a generation token. Cancelling a task is not enough
/// for an iteration that is already on the main actor: a quick pause/resume used
/// to make `isRunning` true again before the old task observed cancellation. The
/// token is invalidated on every stop, so an old task can never step a new run.
struct DemoPlaybackGate: Equatable, Sendable {
    private(set) var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    mutating func end() {
        generation += 1
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}

enum TripControlAction: String, CaseIterable, Sendable {
    case start
    case pause
    case resume
    case reset
}

enum TripControlTarget: Equatable, Sendable {
    case live
    case demo
}

/// One routing table for both the dashboard and the session controls. Starting
/// selects the configured source; pausing, resuming and resetting stay with the
/// demo source only while the demo owns the session.
enum TripControlRouting {
    static func target(
        for action: TripControlAction,
        demoEnabled: Bool,
        demoSessionActive: Bool
    ) -> TripControlTarget {
        switch action {
        case .start:
            return demoEnabled ? .demo : .live
        case .pause, .resume, .reset:
            return demoSessionActive ? .demo : .live
        }
    }
}
