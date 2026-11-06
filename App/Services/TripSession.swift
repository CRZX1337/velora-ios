import Combine
import Foundation

@MainActor
final class TripSession: ObservableObject {
    static let shared = TripSession()

    @Published private(set) var state: TripState = .idle
    /// True as soon as a simulated fix entered this session. Display-only
    /// provenance; it never changes engine or recorder behaviour.
    @Published private(set) var isSimulatedSession = false
    @Published var showingSettings = false
    @Published private(set) var maximumSpeedMetersPerSecond: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    @Published private(set) var speedReading: SpeedReading = .unavailable
    @Published private(set) var motionState: MotionVerdict = .stabilizing
    @Published private(set) var positionMotionStatus: MotionVerdict = .stabilizing
    @Published private(set) var segmentMotionStatus: MotionVerdict = .stabilizing
    @Published private(set) var nativeMotionStatus: MotionVerdict = .stabilizing
    @Published private(set) var statusConflict = false
    @Published private(set) var decisionConflict = false

    @Published private(set) var gapCount = 0
    @Published private(set) var gapSeconds: TimeInterval = 0
    @Published private(set) var pendingSeconds: TimeInterval = 0
    @Published private(set) var pendingSamples = 0
    @Published private(set) var committedSeconds: TimeInterval = 0
    @Published private(set) var stationarySeconds: TimeInterval = 0
    @Published private(set) var lastSegmentResolution: SegmentResolution?
    @Published private(set) var engineDiagnostics = SpeedEngineDiagnostics.placeholder
    @Published private(set) var decimatedSamples = 0
    @Published private(set) var doubleResolutionAttempts = 0
    @Published private(set) var ledgerBalanced = true

    let engine = SpeedEngine()
    let recorder = TripRecorder()

    /// Injectable monotonic clock. Live trips use the system uptime; the demo
    /// source supplies its simulated clock so playback rates stay consistent.
    var monotonicClock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    var averageSpeedMetersPerSecond: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return distanceMeters / elapsedSeconds
    }

    var hasDistanceCoverageGaps: Bool { gapCount > 0 }

    func start(using locationService: LocationService) {
        guard state == .idle else { return }
        maximumSpeedMetersPerSecond = 0
        distanceMeters = 0
        elapsedSeconds = 0
        engine.reset()
        recorder.start(now: monotonicNow())
        state = .running
        isSimulatedSession = false
        locationService.onFix = { [weak self] fix in
            self?.ingest(fix)
        }
        locationService.requestPermission()
        locationService.startUpdates()
        publish(now: monotonicNow())
    }

    func pause(locationService: LocationService) {
        guard state == .running else { return }
        let now = monotonicNow()
        recorder.pause(now: now)
        state = .paused
        publish(now: now)
        locationService.stopUpdates()
    }

    func resume(locationService: LocationService) {
        guard state == .paused else { return }
        let now = monotonicNow()
        recorder.resume(now: now)
        state = .running
        locationService.startUpdates()
        publish(now: now)
    }

    func reset(locationService: LocationService) {
        locationService.stopUpdates()
        locationService.onFix = nil
        engine.reset()
        recorder.reset()
        state = .idle
        maximumSpeedMetersPerSecond = 0
        distanceMeters = 0
        elapsedSeconds = 0
        speedReading = .unavailable
        motionState = .stabilizing
        positionMotionStatus = .stabilizing
        segmentMotionStatus = .stabilizing
        nativeMotionStatus = .stabilizing
        statusConflict = false
        decisionConflict = false
        gapCount = 0
        gapSeconds = 0
        pendingSeconds = 0
        pendingSamples = 0
        committedSeconds = 0
        stationarySeconds = 0
        lastSegmentResolution = nil
        engineDiagnostics = SpeedEngineDiagnostics.placeholder
        decimatedSamples = 0
        doubleResolutionAttempts = 0
        ledgerBalanced = true
        isSimulatedSession = false
    }

    func updateElapsed() {
        // Paused and idle sessions have nothing to advance. Publishing there
        // rebuilt the dashboard every second for unchanged values and could
        // interrupt a touch that had already landed on a control.
        guard state == .running else { return }
        let now = monotonicNow()
        recorder.tick(now: now)
        publish(now: now)
    }

    // MARK: - Ingestion

    private func ingest(_ fix: TripFix) {
        guard state == .running else { return }
        if fix.isSimulated { isSimulatedSession = true }
        engine.ingest(fix)
        recorder.ingest(fix, now: fix.monotonicTime)

        if let speed = engine.reading.metersPerSecond,
           engine.reading.source == .native || engine.reading.source == .derived {
            maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond, speed)
        }
        publish(now: fix.monotonicTime)
    }

    private func publish(now: Double) {
        engine.refresh(now: now)
        let snapshot = recorder.snapshot(now: now)
        distanceMeters = snapshot.distanceMeters
        elapsedSeconds = snapshot.activeSeconds
        gapCount = snapshot.gapCount
        gapSeconds = snapshot.gapSeconds
        pendingSeconds = snapshot.pendingSeconds
        pendingSamples = snapshot.pendingSamples
        committedSeconds = snapshot.committedSeconds
        stationarySeconds = snapshot.stationarySeconds
        lastSegmentResolution = snapshot.lastResolution
        decimatedSamples = snapshot.decimatedSamples
        doubleResolutionAttempts = snapshot.doubleResolutionAttempts
        ledgerBalanced = recorder.ledgerIsBalanced(now: now)
        segmentMotionStatus = snapshot.segmentStatus

        speedReading = engine.reading
        positionMotionStatus = engine.positionMotionStatus
        nativeMotionStatus = engine.nativeMotionStatus
        engineDiagnostics = engine.diagnostics

        fuseMotionState()
    }

    /// Status fusion. Position evidence stays authoritative for segment
    /// resolution; native evidence may only supplement the displayed status.
    private func fuseMotionState() {
        let position = positionMotionStatus
        let segment = segmentMotionStatus
        let native = nativeMotionStatus

        if position != .stabilizing, segment != .stabilizing, position != segment {
            motionState = .stabilizing
            statusConflict = true
            return
        }
        statusConflict = false

        if position != .stabilizing || segment != .stabilizing {
            let decisive = position != .stabilizing ? position : segment
            if native != .stabilizing, native != decisive {
                motionState = .stabilizing
                decisionConflict = true
            } else {
                motionState = decisive
                decisionConflict = false
            }
            return
        }

        decisionConflict = false
        motionState = native
    }

    private func monotonicNow() -> Double {
        monotonicClock()
    }
}
