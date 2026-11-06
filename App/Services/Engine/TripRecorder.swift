import Foundation

public enum TripState: String, Equatable, Sendable {
    case idle
    case running
    case paused
}

/// A single accepted position fix with both time axes.
public struct TripFix: Equatable, Sendable {
    public var id: Int
    public var latitude: Double
    public var longitude: Double
    /// GPS timestamp in seconds since 1970. Used for relative spacing only.
    public var gpsTime: Double
    /// Monotonic receipt time in seconds. Used for every duration.
    public var monotonicTime: Double
    public var horizontalAccuracy: Double
    public var nativeSpeed: Double?
    public var nativeSpeedAccuracy: Double?
    /// Provenance only. Simulated fixes never alter the maths and can never be
    /// mistaken for a recorded GPS session.
    public var isSimulated: Bool

    public init(
        id: Int,
        latitude: Double,
        longitude: Double,
        gpsTime: Double,
        monotonicTime: Double,
        horizontalAccuracy: Double,
        nativeSpeed: Double? = nil,
        nativeSpeedAccuracy: Double? = nil,
        isSimulated: Bool = false
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.gpsTime = gpsTime
        self.monotonicTime = monotonicTime
        self.horizontalAccuracy = horizontalAccuracy
        self.nativeSpeed = nativeSpeed
        self.nativeSpeedAccuracy = nativeSpeedAccuracy
        self.isSimulated = isSimulated
    }

    public var isDistanceEligible: Bool {
        monotonicTime.isFinite
            && latitude.isFinite
            && longitude.isFinite
            && horizontalAccuracy.isFinite
            && horizontalAccuracy > 0
            && horizontalAccuracy <= 35
    }
}

public enum SegmentResolution: String, Equatable, Sendable {
    case committed
    case stationaryZero
    case gap
}

public struct RecorderSnapshot: Equatable, Sendable {
    public var state: TripState
    public var distanceMeters: Double
    public var activeSeconds: Double
    public var committedSeconds: Double
    public var stationarySeconds: Double
    public var gapSeconds: Double
    public var gapCount: Int
    public var pendingSeconds: Double
    public var pendingSamples: Int
    public var segmentStatus: MotionVerdict
    public var lastResolution: SegmentResolution?
    public var decimatedSamples: Int
    public var doubleResolutionAttempts: Int
}

/// Owns the distance ledger. Foundation-only and fully deterministic so the
/// same logic can be exercised by the Windows test harness.
public final class TripRecorder {
    public static let maxPendingDuration: Double = 45
    public static let maxPendingSamples = 480
    private static let checkpoints: [Double] = [6, 12, 20, 30, 45]
    private static let maxSampleGap: Double = 5
    private static let gridInterval: Double = 0.1

    public private(set) var state: TripState = .idle
    public private(set) var distanceMeters: Double = 0
    public private(set) var committedSeconds: Double = 0
    public private(set) var stationarySeconds: Double = 0
    public private(set) var gapSeconds: Double = 0
    public private(set) var gapCount: Int = 0
    public private(set) var segmentStatus: MotionVerdict = .stabilizing
    public private(set) var lastResolution: SegmentResolution?
    public private(set) var decimatedSamples: Int = 0
    public private(set) var doubleResolutionAttempts: Int = 0

    private var activeAccumulated: Double = 0
    private var activeStart: Double?
    private var pausedAt: Double?

    private var pending: [TripFix] = []
    private var segmentStart: Double?
    private var checkpointIndex = 0
    private var segmentID = 0
    private var resolvedSegments: Set<Int> = []
    private var lastAcceptedMonotonic: Double?
    private var lastGridCell: Int?
    private var lastSegmentEnd: Double?

    public init() {}

    // MARK: - Lifecycle

    public func start(now: Double) {
        state = .running
        distanceMeters = 0
        committedSeconds = 0
        stationarySeconds = 0
        gapSeconds = 0
        gapCount = 0
        activeAccumulated = 0
        activeStart = now
        pausedAt = nil
        pending = []
        segmentStart = now
        checkpointIndex = 0
        segmentID = 0
        resolvedSegments = []
        lastAcceptedMonotonic = nil
        lastGridCell = nil
        lastResolution = nil
        segmentStatus = .stabilizing
        decimatedSamples = 0
        doubleResolutionAttempts = 0
        lastSegmentEnd = now
    }

    public func pause(now: Double) {
        guard state == .running else { return }
        resolveCurrent(end: now)
        activeAccumulated += max(0, now - (activeStart ?? now))
        activeStart = nil
        pausedAt = now
        state = .paused
    }

    public func resume(now: Double) {
        guard state == .paused else { return }
        state = .running
        activeStart = now
        pausedAt = nil
        segmentStart = now
        pending = []
        checkpointIndex = 0
        segmentStatus = .stabilizing
        lastGridCell = nil
        lastAcceptedMonotonic = nil
        segmentID += 1
    }

    public func stop(now: Double) {
        guard state == .running else {
            if state == .paused { state = .idle }
            return
        }
        resolveCurrent(end: now)
        activeAccumulated += max(0, now - (activeStart ?? now))
        activeStart = nil
        state = .idle
    }

    public func reset() {
        state = .idle
        distanceMeters = 0
        committedSeconds = 0
        stationarySeconds = 0
        gapSeconds = 0
        gapCount = 0
        activeAccumulated = 0
        activeStart = nil
        pausedAt = nil
        pending = []
        segmentStart = nil
        checkpointIndex = 0
        resolvedSegments = []
        lastAcceptedMonotonic = nil
        lastGridCell = nil
        lastResolution = nil
        segmentStatus = .stabilizing
        decimatedSamples = 0
        doubleResolutionAttempts = 0
        lastSegmentEnd = nil
    }

    // MARK: - Ingestion

    public func ingest(_ fix: TripFix, now: Double) {
        guard state == .running, fix.isDistanceEligible else { return }

        if let lastAcceptedMonotonic, fix.monotonicTime <= lastAcceptedMonotonic {
            return
        }

        if !acceptByGrid(fix) {
            decimatedSamples += 1
            return
        }

        if let last = pending.last, fix.monotonicTime - last.monotonicTime > Self.maxSampleGap {
            let outageStart = last.monotonicTime
            resolveCurrent(end: outageStart)
            gapSeconds += max(0, fix.monotonicTime - outageStart)
            gapCount += 1
            segmentStart = fix.monotonicTime
            pending = []
            checkpointIndex = 0
            segmentStatus = .stabilizing
        }

        if pending.isEmpty {
            if let start = segmentStart, fix.monotonicTime - start > Self.maxSampleGap {
                gapSeconds += max(0, fix.monotonicTime - start)
                gapCount += 1
                segmentStart = fix.monotonicTime
            } else if segmentStart == nil {
                segmentStart = fix.monotonicTime
            }
        }

        pending.append(fix)
        lastAcceptedMonotonic = fix.monotonicTime
        if pending.count > Self.maxPendingSamples {
            // Safety net only; the 45 s limit is reached first at every tested rate.
            resolveCurrent(end: fix.monotonicTime)
            segmentStart = fix.monotonicTime
            pending = [fix]
            checkpointIndex = 0
        }

        evaluateCheckpoints(now: fix.monotonicTime)
    }

    public func tick(now: Double) {
        guard state == .running, let start = segmentStart else { return }
        if now - start >= Self.maxPendingDuration {
            evaluateCheckpoints(now: now)
            if let segmentStart, now - segmentStart >= Self.maxPendingDuration {
                resolveCurrent(end: now)
                self.segmentStart = now
                pending = []
                checkpointIndex = 0
                segmentStatus = .stabilizing
                lastGridCell = nil
                lastAcceptedMonotonic = nil
            }
        }
    }

    // MARK: - Ledger

    public var activeSeconds: Double {
        // `now` is supplied by the caller for running trips via `snapshot(now:)`.
        activeAccumulated
    }

    public func activeSeconds(now: Double) -> Double {
        guard let activeStart else { return activeAccumulated }
        return activeAccumulated + max(0, now - activeStart)
    }

    public func pendingSeconds(now: Double) -> Double {
        guard state == .running, let segmentStart else { return 0 }
        return max(0, now - segmentStart)
    }

    public func snapshot(now: Double) -> RecorderSnapshot {
        RecorderSnapshot(
            state: state,
            distanceMeters: distanceMeters,
            activeSeconds: activeSeconds(now: now),
            committedSeconds: committedSeconds,
            stationarySeconds: stationarySeconds,
            gapSeconds: gapSeconds,
            gapCount: gapCount,
            pendingSeconds: pendingSeconds(now: now),
            pendingSamples: pending.count,
            segmentStatus: segmentStatus,
            lastResolution: lastResolution,
            decimatedSamples: decimatedSamples,
            doubleResolutionAttempts: doubleResolutionAttempts
        )
    }

    /// `active == committed + stationary + gap + pending` must hold at all times.
    public func ledgerIsBalanced(now: Double, tolerance: Double = 0.05) -> Bool {
        let active = activeSeconds(now: now)
        let total = committedSeconds + stationarySeconds + gapSeconds + pendingSeconds(now: now)
        return abs(active - total) <= tolerance
    }

    // MARK: - Internals

    private func acceptByGrid(_ fix: TripFix) -> Bool {
        let cell = Int(floor(fix.monotonicTime / Self.gridInterval))
        if cell == lastGridCell {
            if var last = pending.last, fix.horizontalAccuracy < last.horizontalAccuracy {
                last.horizontalAccuracy = fix.horizontalAccuracy
                last.nativeSpeed = fix.nativeSpeed
                last.nativeSpeedAccuracy = fix.nativeSpeedAccuracy
                pending[pending.count - 1] = last
            }
            return false
        }
        lastGridCell = cell
        return true
    }

    private func evaluateCheckpoints(now: Double) {
        guard let segmentStart else { return }
        let elapsed = now - segmentStart
        while checkpointIndex < Self.checkpoints.count,
              elapsed + 1e-9 >= Self.checkpoints[checkpointIndex] {
            checkpointIndex += 1
            evaluateHalves()
            if pending.isEmpty { return }
        }
    }

    private func evaluateHalves() {
        guard pending.count >= 2 * MotionConstants().minSamples else {
            segmentStatus = .stabilizing
            return
        }
        let verdict = halvesVerdict()
        segmentStatus = verdict
        guard let last = pending.last else { return }
        switch verdict {
        case .moving:
            commit(endingAt: last.monotonicTime)
        case .stationary:
            closeStationary(endingAt: last.monotonicTime)
        case .stabilizing:
            break
        }
    }

    private func halvesVerdict() -> MotionVerdict {
        let split = splitHalves(pending)
        guard let first = split.first, let second = split.second else {
            return .stabilizing
        }
        let firstAnalysis = MotionMath.analyze(points: motionPoints(for: first))
        let secondAnalysis = MotionMath.analyze(points: motionPoints(for: second))

        if firstAnalysis.verdict == .moving, secondAnalysis.verdict == .moving {
            return .moving
        }
        if firstAnalysis.verdict == .stationary, secondAnalysis.verdict == .stationary {
            return .stationary
        }
        return .stabilizing
    }

    private func splitHalves(_ samples: [TripFix]) -> (first: [TripFix]?, second: [TripFix]?) {
        guard samples.count >= 2 else { return (nil, nil) }
        let middle = samples.count / 2
        let first = Array(samples[0..<middle])
        let secondStart = samples.count.isMultiple(of: 2) ? middle : middle + 1
        guard secondStart < samples.count else { return (nil, nil) }
        let second = Array(samples[secondStart...])
        return (first, second)
    }

    private func motionPoints(for samples: [TripFix]) -> [MotionPoint] {
        guard let origin = samples.first else { return [] }
        let originLatitude = origin.latitude * .pi / 180
        return samples.map { sample in
            let deltaLatitude = (sample.latitude - origin.latitude) * .pi / 180
            let deltaLongitude = (sample.longitude - origin.longitude) * .pi / 180
            let x = deltaLongitude * cos(originLatitude) * MotionMath.earthRadius
            let y = deltaLatitude * MotionMath.earthRadius
            return MotionPoint(
                id: sample.id,
                t: sample.gpsTime,
                x: x,
                y: y,
                accuracy: sample.horizontalAccuracy
            )
        }
    }

    private func resolveCurrent(end: Double) {
        guard let segmentStart else { return }
        if resolvedSegments.contains(segmentID) {
            doubleResolutionAttempts += 1
            return
        }
        let clippedEnd = max(end, segmentStart)
        guard !pending.isEmpty || clippedEnd > segmentStart + 1e-6 else { return }
        resolvedSegments.insert(segmentID)

        let lastMonotonic = pending.last?.monotonicTime ?? segmentStart
        let verdict = pending.isEmpty ? MotionVerdict.stabilizing : halvesVerdict()
        segmentStatus = verdict

        let covered = max(0, lastMonotonic - segmentStart)
        switch verdict {
        case .moving:
            distanceMeters += pathDistance(pending)
            committedSeconds += covered
            lastResolution = .committed
        case .stationary:
            stationarySeconds += covered
            lastResolution = .stationaryZero
        case .stabilizing:
            if covered > 0 {
                gapSeconds += covered
                gapCount += 1
            }
            lastResolution = .gap
        }

        let tail = max(0, clippedEnd - lastMonotonic)
        if tail > 1e-6 {
            switch verdict {
            case .moving:
                if tail <= Self.maxSampleGap {
                    committedSeconds += tail
                } else {
                    gapSeconds += tail
                    gapCount += 1
                }
            case .stationary:
                if tail <= Self.maxSampleGap {
                    stationarySeconds += tail
                } else {
                    gapSeconds += tail
                    gapCount += 1
                }
            case .stabilizing:
                gapSeconds += tail
                gapCount += 1
            }
        }

        pending = []
        checkpointIndex = 0
        self.segmentStart = clippedEnd
        lastSegmentEnd = clippedEnd
        lastGridCell = nil
        lastAcceptedMonotonic = nil
        segmentStatus = verdict
        segmentID += 1
    }

    private func commit(endingAt end: Double) {
        guard let segmentStart else { return }
        if resolvedSegments.contains(segmentID) {
            doubleResolutionAttempts += 1
            return
        }
        resolvedSegments.insert(segmentID)
        distanceMeters += pathDistance(pending)
        committedSeconds += max(0, end - segmentStart)
        lastResolution = .committed
        finishSegment(at: end)
    }

    private func closeStationary(endingAt end: Double) {
        guard let segmentStart else { return }
        if resolvedSegments.contains(segmentID) {
            doubleResolutionAttempts += 1
            return
        }
        resolvedSegments.insert(segmentID)
        stationarySeconds += max(0, end - segmentStart)
        lastResolution = .stationaryZero
        finishSegment(at: end)
    }

    private func finishSegment(at end: Double) {
        pending = []
        checkpointIndex = 0
        segmentStart = end
        lastSegmentEnd = end
        lastGridCell = nil
        lastAcceptedMonotonic = nil
        segmentStatus = .stabilizing
        segmentID += 1
    }

    private func pathDistance(_ samples: [TripFix]) -> Double {
        guard samples.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let interval = current.monotonicTime - previous.monotonicTime
            guard interval > 0, interval <= Self.maxSampleGap else { continue }
            guard previous.isDistanceEligible, current.isDistanceEligible else { continue }
            total += MotionMath.haversine(
                latitude1: previous.latitude,
                longitude1: previous.longitude,
                latitude2: current.latitude,
                longitude2: current.longitude
            )
        }
        return total
    }
}
