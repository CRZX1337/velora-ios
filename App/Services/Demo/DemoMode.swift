import Combine
import CoreLocation
import Foundation

/// Drives the demo source. It owns timing and presentation only; every sample
/// goes through `LocationService` into the same `SpeedEngine` / `TripRecorder`
/// path as live GPS.
@MainActor
final class DemoMode: ObservableObject {
    static let shared = DemoMode()

    private static let enabledKey = "demoModeEnabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var session = DemoSessionState()

    var isRunning: Bool { session.isRunning }
    var isPaused: Bool { session.isPaused }
    var isStopped: Bool { session.isStopped }
    var hasSession: Bool { session.hasSession }

    @Published private(set) var profile: DemoDriveProfile = .city
    @Published private(set) var rate: Double = 1
    @Published private(set) var accuracyMeters: Double = 6
    @Published private(set) var signalMode: DemoSignalMode = .live
    @Published private(set) var customTargetKPH: Double = 80
    @Published private(set) var customAcceleration: Double = 9
    @Published private(set) var customDuration: TimeInterval = 60
    @Published private(set) var isManualStillness = false

    @Published private(set) var simulatedSpeedKPH: Double = 0
    @Published private(set) var simulatedDistanceMeters: Double = 0
    @Published private(set) var simulatedElapsed: TimeInterval = 0

    private var timeline: DemoDriveTimeline
    private var loopTask: Task<Void, Never>?
    private var playback = DemoPlaybackGate()
    private var demoMonotonic: TimeInterval = 0
    private var demoDate = Date()
    private var failureReported = false

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        timeline = DemoDriveTimeline(configuration: DemoDriveConfiguration())
    }

    // MARK: - Presentation

    var rateLabel: String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : String(format: "%.1f×", rate)
    }

    var statusText: String {
        if !isEnabled { return "Off" }
        switch session.phase {
        case .idle: return "Ready"
        case .running: return "Running · \(rateLabel)"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    var badgeText: String {
        switch session.phase {
        case .paused: return "DEMO MODE · PAUSED"
        case .stopped: return "DEMO MODE · STOPPED"
        case .running: return "DEMO MODE · \(rateLabel)"
        case .idle: return "DEMO MODE"
        }
    }

    // MARK: - Mode

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if !enabled {
            reset()
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    #if DEBUG
    /// Snapshot-only: enables the mode without persisting it, so later
    /// screenshots in the same simulator are unaffected.
    func enableForSnapshot() {
        isEnabled = true
    }
    #endif

    func setProfile(_ profile: DemoDriveProfile) {
        guard !hasSession else { return }
        self.profile = profile
        timeline = DemoDriveTimeline(configuration: configuration)
        resetReadouts()
        isManualStillness = false
    }

    func setRate(_ rate: Double) {
        let clamped = min(max(rate, 0.5), 10)
        self.rate = clamped
        timeline.configuration.rate = clamped
    }

    func setAccuracy(_ accuracy: Double) {
        let clamped = min(max(accuracy, 3), 120)
        accuracyMeters = clamped
        timeline.configuration.accuracyMeters = clamped
    }

    func setSignalMode(_ mode: DemoSignalMode) {
        signalMode = mode
        timeline.configuration.signalMode = mode

        guard hasSession else { return }
        if mode == .live {
            failureReported = false
            LocationService.shared.clearDemoFailure()
        } else if mode == .error {
            failureReported = true
            LocationService.shared.reportDemoFailure()
        }
    }

    func setCustomTarget(_ speedKPH: Double) {
        let clamped = min(max(speedKPH, 0), 200)
        customTargetKPH = clamped
        timeline.configuration.customTargetKPH = clamped
    }

    func setCustomAcceleration(_ acceleration: Double) {
        let clamped = min(max(acceleration, 1), 30)
        customAcceleration = clamped
        timeline.configuration.customAccelerationKPHPerSecond = clamped
    }

    func setCustomDuration(_ duration: TimeInterval) {
        let clamped = min(max(duration, 10), 300)
        customDuration = clamped
        timeline.configuration.customDuration = clamped
    }

    func setManualStillness(_ still: Bool) {
        guard profile == .custom else { return }
        isManualStillness = still
        timeline.setManualTarget(still ? 0 : nil)
    }

    // MARK: - Session

    func start() {
        guard isEnabled else { return }

        // Starting is idempotent while a session is running or paused. A second
        // tap on a not-yet-redrawn Start button must not reset and restart the
        // trip. Only an explicitly stopped session starts a fresh one.
        switch session.phase {
        case .running, .paused:
            return
        case .stopped:
            reset()
        case .idle:
            break
        }
        guard session.phase == .idle else { return }

        let trip = TripSession.shared
        guard trip.state == .idle else { return }

        demoMonotonic = 0
        demoDate = Date()
        failureReported = false
        timeline = DemoDriveTimeline(configuration: configuration)
        resetReadouts()

        let location = LocationService.shared
        location.enterDemoSource { [weak self] in self?.demoDate ?? .now }
        trip.monotonicClock = { [weak self] in self?.demoMonotonic ?? 0 }
        trip.start(using: location)

        guard trip.state == .running else {
            location.leaveDemoSource()
            trip.monotonicClock = { ProcessInfo.processInfo.systemUptime }
            return
        }

        var next = session
        guard next.begin() else { return }
        session = next
        startLoop()
    }

    func pause() {
        let trip = TripSession.shared
        guard session.isRunning, trip.state == .running else { return }

        trip.pause(locationService: LocationService.shared)
        guard trip.state == .paused else { return }

        stopLoop()
        var next = session
        guard next.pause() else { return }
        session = next
    }

    func stop() {
        let trip = TripSession.shared
        guard session.phase == .running || session.phase == .paused,
              trip.state == .running || trip.state == .paused else { return }

        if trip.state == .running {
            trip.pause(locationService: LocationService.shared)
        }
        guard trip.state == .paused else { return }

        stopLoop()
        var next = session
        guard next.stop() else { return }
        session = next
    }

    func resume() {
        let trip = TripSession.shared
        guard session.isPaused, session.hasSession, trip.state == .paused else { return }

        trip.resume(locationService: LocationService.shared)
        guard trip.state == .running else { return }

        var next = session
        guard next.resume() else {
            trip.pause(locationService: LocationService.shared)
            return
        }
        session = next
        startLoop()
    }

    func reset() {
        stopLoop()

        if session.hasSession {
            TripSession.shared.reset(locationService: LocationService.shared)
        }
        LocationService.shared.leaveDemoSource()
        TripSession.shared.monotonicClock = { ProcessInfo.processInfo.systemUptime }

        var next = session
        _ = next.reset()
        session = next
        failureReported = false
        isManualStillness = false
        timeline = DemoDriveTimeline(configuration: configuration)
        resetReadouts()
    }

    // MARK: - Playback

    private func startLoop() {
        stopLoop()
        let token = playback.begin()
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self,
                      !Task.isCancelled,
                      self.playback.isCurrent(token),
                      self.session.isRunning,
                      TripSession.shared.state == .running else { return }
                self.step()
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        playback.end()
    }

    private func step() {
        let previousElapsed = timeline.elapsed
        let sample = timeline.advance(by: 0.1)
        let advanced = sample.elapsed - previousElapsed
        demoMonotonic += advanced
        demoDate = demoDate.addingTimeInterval(advanced)

        simulatedSpeedKPH = sample.speedKPH
        simulatedDistanceMeters = sample.distanceMeters
        simulatedElapsed = sample.elapsed

        if sample.hasFix {
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: sample.latitude,
                    longitude: sample.longitude
                ),
                altitude: 0,
                horizontalAccuracy: sample.accuracyMeters,
                verticalAccuracy: -1,
                course: 38,
                courseAccuracy: -1,
                speed: max(0, sample.speedKPH / 3.6),
                speedAccuracy: 0.5,
                timestamp: demoDate
            )
            LocationService.shared.feedDemoSample(location, monotonicTime: demoMonotonic)
        }

        if signalMode == .error, !failureReported {
            failureReported = true
            LocationService.shared.reportDemoFailure()
        } else if signalMode == .live, failureReported {
            failureReported = false
            LocationService.shared.clearDemoFailure()
        }

        TripSession.shared.updateElapsed()
    }

    private func resetReadouts() {
        simulatedSpeedKPH = 0
        simulatedDistanceMeters = 0
        simulatedElapsed = 0
    }

    private var configuration: DemoDriveConfiguration {
        DemoDriveConfiguration(
            profile: profile,
            rate: rate,
            accuracyMeters: accuracyMeters,
            initialFixDelay: 2,
            signalMode: signalMode,
            customTargetKPH: customTargetKPH,
            customAccelerationKPHPerSecond: customAcceleration,
            customDuration: customDuration
        )
    }
}
