import Foundation

public struct SpeedReading: Equatable, Sendable {
    public enum Source: String, Sendable {
        case native
        case derived
        case held
        case unavailable
    }

    public var metersPerSecond: Double?
    public var source: Source
    public var age: Double
    public var isHeld: Bool

    public static let unavailable = SpeedReading(
        metersPerSecond: nil,
        source: .unavailable,
        age: .infinity,
        isHeld: false
    )
}

public struct SpeedEngineDiagnostics: Equatable, Sendable {
    public var windowCount: Int
    public var sampleCount: Int
    public var speed: Double
    public var standardError: Double
    public var resolution: Double
    public var margin: Double
    public var rss0: Double
    public var rss1: Double
    public var fStatistic: Double?
    public var reason: String
    public var medianAccuracy: Double
    public var windowSpan: Double
    public var currentSampleIDs: [Int]
    public var previousSampleIDs: [Int]
    public var nativeReason: String
    public var decimatedSamples: Int

    public static let placeholder = SpeedEngineDiagnostics(
        windowCount: 0,
        sampleCount: 0,
        speed: 0,
        standardError: 0,
        resolution: 0,
        margin: 0,
        rss0: 0,
        rss1: 0,
        fStatistic: nil,
        reason: "idle",
        medianAccuracy: 0,
        windowSpan: 0,
        currentSampleIDs: [],
        previousSampleIDs: [],
        nativeReason: "idle",
        decimatedSamples: 0
    )
}

/// Central, Foundation-only speed engine. Owns the motion ring, the native
/// observation channel and the derived window analysis.
public final class SpeedEngine {
    public static let windowSpan: Double = 12
    public static let minWindowSamples = 6
    public static let minWindowSpan: Double = 6
    public static let maxSampleGap: Double = 5
    public static let retention: Double = 40
    public static let ringCapacity = 200
    public static let nativeMaxAge: Double = 2.0
    public static let derivedMaxAge: Double = 2.5
    public static let nativePairingGap: Double = 3.0

    public private(set) var reading: SpeedReading = .unavailable
    public private(set) var positionMotionStatus: MotionVerdict = .stabilizing
    public private(set) var nativeMotionStatus: MotionVerdict = .stabilizing
    public private(set) var diagnostics = SpeedEngineDiagnostics(
        windowCount: 0,
        sampleCount: 0,
        speed: 0,
        standardError: 0,
        resolution: 0,
        margin: 0,
        rss0: 0,
        rss1: 0,
        fStatistic: nil,
        reason: "idle",
        medianAccuracy: 0,
        windowSpan: 0,
        currentSampleIDs: [],
        previousSampleIDs: [],
        nativeReason: "idle",
        decimatedSamples: 0
    )

    private struct RingSample {
        var id: Int
        var latitude: Double
        var longitude: Double
        var gpsTime: Double
        var monotonicTime: Double
        var accuracy: Double
    }

    private var ring: [RingSample] = []
    private var bucketKey: Int?
    private var bucketSamples = 0
    private var decimatedSamples = 0

    private var lastValidReading: (speed: Double, source: SpeedReading.Source, mono: Double)?
    private var lastNativeVerdict: MotionVerdict?
    private var lastNativeMono: Double?
    private var nativeReason = "idle"
    private var currentAnalysis: WindowAnalysis?
    private var previousAnalysis: WindowAnalysis?

    public init() {}

    public func reset() {
        ring = []
        bucketKey = nil
        bucketSamples = 0
        decimatedSamples = 0
        lastValidReading = nil
        lastNativeVerdict = nil
        lastNativeMono = nil
        nativeReason = "idle"
        currentAnalysis = nil
        previousAnalysis = nil
        reading = .unavailable
        positionMotionStatus = .stabilizing
        nativeMotionStatus = .stabilizing
    }

    public func ingest(_ fix: TripFix) {
        let positionEligible = fix.latitude.isFinite
            && fix.longitude.isFinite
            && fix.gpsTime.isFinite
            && fix.horizontalAccuracy.isFinite
            && fix.horizontalAccuracy > 0
            && fix.horizontalAccuracy <= MotionConstants().motionMaxAccuracy

        if positionEligible, insertIntoRing(fix) {
            evaluateWindows()
        }

        if let speed = validatedNative(fix) {
            updateNative(speed: speed, fix: fix)
        } else {
            nativeMotionStatus = .stabilizing
            nativeReason = "noValidNativeObservation"
            lastNativeVerdict = nil
            lastNativeMono = nil
        }

        refresh(now: fix.monotonicTime)
    }

    public func refresh(now: Double) {
        if let last = lastValidReading, last.source == .native {
            let age = now - last.mono
            if age <= Self.nativeMaxAge {
                reading = SpeedReading(
                    metersPerSecond: last.speed,
                    source: .native,
                    age: age,
                    isHeld: false
                )
                return
            }
        }

        if let analysis = currentAnalysis, canDisplayDerived(analysis, now: now) {
            let age = ageOfCurrentWindow(now: now)
            reading = SpeedReading(
                metersPerSecond: analysis.speed,
                source: .derived,
                age: age,
                isHeld: false
            )
            if let reference = ring.last {
                lastValidReading = (analysis.speed, .derived, reference.monotonicTime)
            }
            return
        }

        if let last = lastValidReading {
            let age = now - last.mono
            if age <= Self.nativeMaxAge {
                reading = SpeedReading(
                    metersPerSecond: last.speed,
                    source: .held,
                    age: age,
                    isHeld: true
                )
                return
            }
        }

        reading = .unavailable
    }

    // MARK: - Ring

    private func insertIntoRing(_ fix: TripFix) -> Bool {
        guard ring.last.map({ fix.monotonicTime > $0.monotonicTime }) ?? true else {
            return false
        }

        let key = Int(floor(fix.monotonicTime / 0.5))
        if let bucketKey, key == bucketKey {
            bucketSamples += 1
            if bucketSamples > 2, !ring.isEmpty {
                decimatedSamples += 1
                ring[ring.count - 1] = sample(from: fix)
            } else {
                ring.append(sample(from: fix))
            }
        } else {
            bucketKey = key
            bucketSamples = 1
            ring.append(sample(from: fix))
        }

        let cutoff = fix.monotonicTime - Self.retention
        if let firstKept = ring.firstIndex(where: { $0.monotonicTime >= cutoff }), firstKept > 0 {
            ring.removeFirst(firstKept)
        }
        if ring.count > Self.ringCapacity {
            ring.removeFirst(ring.count - Self.ringCapacity)
        }
        return true
    }

    private func sample(from fix: TripFix) -> RingSample {
        RingSample(
            id: fix.id,
            latitude: fix.latitude,
            longitude: fix.longitude,
            gpsTime: fix.gpsTime,
            monotonicTime: fix.monotonicTime,
            accuracy: fix.horizontalAccuracy
        )
    }

    // MARK: - Windows

    private func evaluateWindows() {
        guard let reference = ring.last else {
            positionMotionStatus = .stabilizing
            return
        }
        let tRef = reference.gpsTime

        let currentSamples = ring.filter {
            $0.gpsTime > tRef - Self.windowSpan && $0.gpsTime <= tRef
        }
        let previousSamples = ring.filter {
            $0.gpsTime > tRef - 2 * Self.windowSpan && $0.gpsTime <= tRef - Self.windowSpan
        }

        guard currentSamples.count >= Self.minWindowSamples,
              previousSamples.count >= Self.minWindowSamples
        else {
            positionMotionStatus = .stabilizing
            currentAnalysis = nil
            previousAnalysis = nil
            updateDiagnostics()
            return
        }

        guard let current = analyze(window: currentSamples),
              let previous = analyze(window: previousSamples)
        else {
            positionMotionStatus = .stabilizing
            currentAnalysis = nil
            previousAnalysis = nil
            updateDiagnostics()
            return
        }

        currentAnalysis = current
        previousAnalysis = previous
        updateDiagnostics()

        guard let confirmed = MotionMath.confirm(current: current, previous: previous) else {
            positionMotionStatus = .stabilizing
            return
        }
        positionMotionStatus = confirmed.verdict
    }

    private func updateDiagnostics() {
        guard let analysis = currentAnalysis else {
            diagnostics = SpeedEngineDiagnostics(
                windowCount: ring.count,
                sampleCount: 0,
                speed: 0,
                standardError: 0,
                resolution: 0,
                margin: 0,
                rss0: 0,
                rss1: 0,
                fStatistic: nil,
                reason: "insufficientWindow",
                medianAccuracy: 0,
                windowSpan: 0,
                currentSampleIDs: [],
                previousSampleIDs: previousAnalysis?.sampleIDs ?? [],
                nativeReason: nativeReason,
                decimatedSamples: decimatedSamples
            )
            return
        }
        diagnostics = SpeedEngineDiagnostics(
            windowCount: ring.count,
            sampleCount: analysis.usedCount,
            speed: analysis.speed,
            standardError: analysis.standardError,
            resolution: analysis.resolution,
            margin: analysis.margin,
            rss0: analysis.rss0,
            rss1: analysis.rss1,
            fStatistic: analysis.fStatistic,
            reason: analysis.reason,
            medianAccuracy: analysis.medianAccuracy,
            windowSpan: analysis.span,
            currentSampleIDs: analysis.sampleIDs,
            previousSampleIDs: previousAnalysis?.sampleIDs ?? [],
            nativeReason: nativeReason,
            decimatedSamples: decimatedSamples
        )
    }

    private func analyze(window: [RingSample]) -> WindowAnalysis? {
        guard let origin = window.first else { return nil }
        let originLatitude = origin.latitude * .pi / 180
        let points = window.map { sample -> MotionPoint in
            let deltaLatitude = (sample.latitude - origin.latitude) * .pi / 180
            let deltaLongitude = (sample.longitude - origin.longitude) * .pi / 180
            return MotionPoint(
                id: sample.id,
                t: sample.gpsTime,
                x: deltaLongitude * cos(originLatitude) * MotionMath.earthRadius,
                y: deltaLatitude * MotionMath.earthRadius,
                accuracy: sample.accuracy
            )
        }
        return MotionMath.analyze(points: points)
    }

    // MARK: - Display quality

    private func canDisplayDerived(_ analysis: WindowAnalysis, now: Double) -> Bool {
        guard analysis.isModelConsistent,
              analysis.usedCount >= Self.minWindowSamples,
              analysis.span >= Self.minWindowSpan,
              analysis.speed.isFinite,
              analysis.standardError.isFinite,
              ageOfCurrentWindow(now: now) <= Self.derivedMaxAge
        else { return false }

        let allowed = max(0.2, min(1.5, 0.2 * analysis.speed))
        return analysis.standardError <= allowed
    }

    private func ageOfCurrentWindow(now: Double) -> Double {
        guard let reference = ring.last else { return .infinity }
        return max(0, now - reference.monotonicTime)
    }

    // MARK: - Native channel

    private func validatedNative(_ fix: TripFix) -> Double? {
        guard let speed = fix.nativeSpeed, let accuracy = fix.nativeSpeedAccuracy else {
            return nil
        }
        guard speed.isFinite, speed >= 0, speed <= 100 else { return nil }
        guard accuracy.isFinite, accuracy >= 0 else { return nil }
        guard fix.horizontalAccuracy.isFinite,
              fix.horizontalAccuracy > 0,
              fix.horizontalAccuracy <= MotionConstants().motionMaxAccuracy
        else { return nil }
        let allowed = max(0.6, min(1.0, 0.08 * speed))
        guard accuracy <= allowed else { return nil }
        return speed
    }

    private func updateNative(speed: Double, fix: TripFix) {
        let accuracy = fix.nativeSpeedAccuracy ?? 0
        let lower = max(0, speed - accuracy)
        let upper = speed + accuracy

        let verdict: MotionVerdict
        if upper <= 0.2, speed <= 0.5, accuracy <= 0.6 {
            verdict = .stationary
            nativeReason = "nativeStationary"
        } else if lower > 0.3 {
            verdict = .moving
            nativeReason = "nativeMoving"
        } else {
            verdict = .stabilizing
            nativeReason = "nativeAmbiguous"
        }

        if let lastNativeVerdict,
           let lastNativeMono,
           lastNativeVerdict == verdict,
           fix.monotonicTime - lastNativeMono <= Self.nativePairingGap,
           verdict != .stabilizing {
            nativeMotionStatus = verdict
        } else {
            nativeMotionStatus = .stabilizing
        }

        lastNativeVerdict = verdict
        lastNativeMono = fix.monotonicTime

        if verdict != .stabilizing {
            lastValidReading = (speed, .native, fix.monotonicTime)
        }
        reading = SpeedReading(
            metersPerSecond: speed,
            source: .native,
            age: 0,
            isHeld: false
        )
    }
}
