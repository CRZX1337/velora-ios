import Foundation

/// Outcome of a single motion window (SpeedEngine window or distance-buffer half).
public enum MotionVerdict: String, Equatable, Sendable {
    case stationary
    case moving
    case stabilizing
}

/// A position sample expressed in a local planar projection (metres).
public struct MotionPoint: Equatable, Sendable {
    public var id: Int
    /// GPS timestamp in seconds. Relative spacing only; never wall-clock arithmetic.
    public var t: Double
    public var x: Double
    public var y: Double
    /// Reported horizontal accuracy (radius), *not* a Gaussian standard deviation.
    public var accuracy: Double

    public init(id: Int, t: Double, x: Double, y: Double, accuracy: Double) {
        self.id = id
        self.t = t
        self.x = x
        self.y = y
        self.accuracy = accuracy
    }
}

public struct MotionConstants: Sendable {
    public var stationaryMaxSpeed: Double = 0.2
    public var movingEvidenceMinimum: Double = 0.3
    public var stationaryFMax: Double = 3.0
    public var resolutionFactor: Double = 1.25
    public var minSamples: Int = 6
    public var minSpan: Double = 6.0
    public var maxSampleGap: Double = 5.0
    public var motionMaxAccuracy: Double = 20.0
    public var outlierRNorm: Double = 3.0
    public var nearZeroResidualFactor: Double = 0.01

    public init() {}
}

/// Full, auditable result of analysing one window.
public struct WindowAnalysis: Equatable, Sendable {
    public var verdict: MotionVerdict
    public var reason: String
    public var sampleIDs: [Int]
    public var usedCount: Int
    public var span: Double
    public var speed: Double
    public var standardError: Double
    public var resolution: Double
    public var margin: Double
    public var rss0: Double
    public var rss1: Double
    public var fStatistic: Double?
    public var medianAccuracy: Double
    public var removedOutlierID: Int?
    public var isModelConsistent: Bool
    public var usedInvariantTolerance: Double

    public static func rejected(_ reason: String) -> WindowAnalysis {
        WindowAnalysis(
            verdict: .stabilizing,
            reason: reason,
            sampleIDs: [],
            usedCount: 0,
            span: 0,
            speed: 0,
            standardError: 0,
            resolution: 0,
            margin: 0,
            rss0: 0,
            rss1: 0,
            fStatistic: nil,
            medianAccuracy: 0,
            removedOutlierID: nil,
            isModelConsistent: false,
            usedInvariantTolerance: 0
        )
    }
}

public enum MotionMath {
    public static let earthRadius = 6_371_008.8

    // MARK: - Public analysis

    public static func analyze(
        points: [MotionPoint],
        constants: MotionConstants = MotionConstants()
    ) -> WindowAnalysis {
        let eligible = points.filter { point in
            point.t.isFinite
                && point.x.isFinite
                && point.y.isFinite
                && point.accuracy.isFinite
                && point.accuracy > 0
                && point.accuracy <= constants.motionMaxAccuracy
        }.sorted { $0.t < $1.t }

        guard eligible.count >= constants.minSamples else {
            return .rejected("insufficientSamples")
        }
        guard !hasGap(eligible, maxGap: constants.maxSampleGap) else {
            return .rejected("sampleGap")
        }

        var used = eligible
        var removedID: Int?

        // Outlier pass: at most one removal. The minimum-sample rule applies
        // *after* this pass, so a six-sample window that loses a point becomes invalid.
        if let firstFit = fit(used), used.count >= 2 {
            var worst: (index: Int, rNorm: Double)?
            var bestNorm = 0.0
            for index in used.indices {
                let rNorm = hypot(firstFit.residualX[index], firstFit.residualY[index])
                    / max(used[index].accuracy, 0.5)
                if rNorm > bestNorm {
                    bestNorm = rNorm
                    worst = (index, rNorm)
                }
            }
            if let worst, bestNorm > constants.outlierRNorm {
                removedID = used[worst.index].id
                used.remove(at: worst.index)
            }
        }

        guard used.count >= constants.minSamples else {
            return .rejected("outlierReducedBelowMinimum")
        }

        let span = (used.last?.t ?? 0) - (used.first?.t ?? 0)
        guard span >= constants.minSpan else {
            return .rejected("spanTooShort")
        }
        guard !hasGap(used, maxGap: constants.maxSampleGap) else {
            return .rejected("sampleGap")
        }
        guard let fit = fit(used), fit.sxx > 1e-9 else {
            return .rejected("degenerateTime")
        }

        let medianAccuracy = median(used.map(\.accuracy))
        let invariantTolerance = max(1e-12, 128 * Double.ulpOfOne * max(fit.rss0, fit.rss1))

        if fit.rss0 < fit.rss1 - invariantTolerance {
            var analysis = baseAnalysis(
                used: used,
                fit: fit,
                span: span,
                medianAccuracy: medianAccuracy,
                removedID: removedID
            )
            analysis.verdict = .stabilizing
            analysis.reason = "modelInconsistent"
            analysis.isModelConsistent = false
            analysis.fStatistic = nil
            analysis.usedInvariantTolerance = invariantTolerance
            return analysis
        }

        let nearZero = pow(constants.nearZeroResidualFactor * max(medianAccuracy, 1.0), 2) * Double(used.count)
        let ambiguity = 4 * nearZero

        var analysis = baseAnalysis(
            used: used,
            fit: fit,
            span: span,
            medianAccuracy: medianAccuracy,
            removedID: removedID
        )
        analysis.usedInvariantTolerance = invariantTolerance

        // Case A: both residuals numerically negligible.
        if fit.rss0 <= nearZero, fit.rss1 <= nearZero {
            if fit.speed <= constants.stationaryMaxSpeed {
                analysis.verdict = .stationary
                analysis.reason = "stationaryNearZero"
            } else {
                applyMovement(&analysis, constants: constants, reason: "movingNearZero")
            }
            return analysis
        }

        // Case B: only the motion model fits; a small RSS1 must never imply F = 0.
        if fit.rss1 <= nearZero, fit.rss0 > ambiguity {
            applyMovement(&analysis, constants: constants, reason: "movingModelExplainsData")
            return analysis
        }

        // Case C: ambiguous near-zero region -> no decision, F is not evaluated.
        if fit.rss1 <= ambiguity, fit.rss0 > nearZero, fit.rss0 <= ambiguity {
            analysis.verdict = .stabilizing
            analysis.reason = "rssAmbiguous"
            return analysis
        }

        // Case D: structurally impossible (constant model fits, motion model does not).
        if fit.rss0 <= nearZero, fit.rss1 > nearZero {
            analysis.verdict = .stabilizing
            analysis.reason = "modelInconsistent"
            analysis.isModelConsistent = false
            return analysis
        }

        // Case E: regular F test.
        guard let f = fStatistic(rss0: fit.rss0, rss1: fit.rss1, sampleCount: used.count) else {
            analysis.verdict = .stabilizing
            analysis.reason = "invalidF"
            return analysis
        }
        analysis.fStatistic = f

        let isStationary = f <= constants.stationaryFMax
            && fit.speed <= constants.stationaryMaxSpeed
        let isMoving = analysis.margin > constants.movingEvidenceMinimum

        if isStationary && isMoving {
            analysis.verdict = .stabilizing
            analysis.reason = "decisionConflict"
        } else if isStationary {
            analysis.verdict = .stationary
            analysis.reason = "stationaryFTest"
        } else if isMoving {
            analysis.verdict = .moving
            analysis.reason = "movingMargin"
        } else {
            analysis.verdict = .stabilizing
            analysis.reason = f > constants.stationaryFMax ? "stationaryRejectedByF" : "insufficientMovementMargin"
        }
        return analysis
    }

    /// Two disjoint windows are required for a confirmation.
    public static func confirm(
        current: WindowAnalysis,
        previous: WindowAnalysis
    ) -> WindowAnalysis? {
        guard !current.sampleIDs.isEmpty, !previous.sampleIDs.isEmpty else { return nil }
        let overlap = Set(current.sampleIDs).intersection(Set(previous.sampleIDs))
        guard overlap.isEmpty else { return nil }

        if current.verdict == .moving, previous.verdict == .moving {
            return current
        }
        if current.verdict == .stationary, previous.verdict == .stationary {
            return current
        }
        return nil
    }

    // MARK: - Helpers

    public static func invariantTolerance(rss0: Double, rss1: Double) -> Double {
        max(1e-12, 128 * Double.ulpOfOne * max(rss0, rss1))
    }

    /// Numerically stable F statistic.
    ///
    /// A negative difference inside the floating-point invariant tolerance is
    /// clamped to zero; a real inconsistency returns `nil` and must be treated
    /// as `modelInconsistent` by the caller.
    public static func fStatistic(rss0: Double, rss1: Double, sampleCount n: Int) -> Double? {
        guard n >= 6, rss0.isFinite, rss1.isFinite else { return nil }
        if rss0 < rss1 - invariantTolerance(rss0: rss0, rss1: rss1) {
            return nil
        }
        let numerator = max(0, rss0 - rss1)
        let degreesOfFreedom = 2.0 * Double(n) - 4.0
        guard degreesOfFreedom > 0 else { return nil }
        let denominator = rss1 / degreesOfFreedom
        guard denominator.isFinite, denominator > 0 else { return nil }
        let f = (numerator / 2.0) / denominator
        guard f.isFinite, f >= 0 else { return nil }
        return f
    }

    private struct Fit {
        var n: Int
        var weights: [Double]
        var meanT: Double
        var meanX: Double
        var meanY: Double
        var sxx: Double
        var vx: Double
        var vy: Double
        var rss0: Double
        var rss1: Double
        var rssX: Double
        var rssY: Double
        var rssXY: Double
        var residualX: [Double]
        var residualY: [Double]
        var speed: Double
        var standardError: Double
    }

    private static func fit(_ points: [MotionPoint]) -> Fit? {
        guard points.count >= 4 else { return nil }

        let raw = points.map { 1.0 / pow(max($0.accuracy, 0.5), 2) }
        let meanRaw = raw.reduce(0, +) / Double(raw.count)
        guard meanRaw > 0, meanRaw.isFinite else { return nil }
        let weights = raw.map { $0 / meanRaw }
        let weightSum = weights.reduce(0, +)
        guard weightSum > 0 else { return nil }

        var meanT = 0.0
        var meanX = 0.0
        var meanY = 0.0
        for index in points.indices {
            meanT += weights[index] * points[index].t
            meanX += weights[index] * points[index].x
            meanY += weights[index] * points[index].y
        }
        meanT /= weightSum
        meanX /= weightSum
        meanY /= weightSum

        var sxx = 0.0
        for index in points.indices {
            let dt = points[index].t - meanT
            sxx += weights[index] * dt * dt
        }
        guard sxx > 1e-9, sxx.isFinite else { return nil }

        var sxtX = 0.0
        var sxtY = 0.0
        var rss0 = 0.0
        for index in points.indices {
            let dt = points[index].t - meanT
            let dx = points[index].x - meanX
            let dy = points[index].y - meanY
            sxtX += weights[index] * dt * dx
            sxtY += weights[index] * dt * dy
            rss0 += weights[index] * (dx * dx + dy * dy)
        }

        let vx = sxtX / sxx
        let vy = sxtY / sxx

        var residualX = [Double](repeating: 0, count: points.count)
        var residualY = [Double](repeating: 0, count: points.count)
        var rss1 = 0.0
        var rssX = 0.0
        var rssY = 0.0
        var rssXY = 0.0
        for index in points.indices {
            let dt = points[index].t - meanT
            let rx = points[index].x - (meanX + vx * dt)
            let ry = points[index].y - (meanY + vy * dt)
            residualX[index] = rx
            residualY[index] = ry
            rss1 += weights[index] * (rx * rx + ry * ry)
            rssX += weights[index] * rx * rx
            rssY += weights[index] * ry * ry
            rssXY += weights[index] * rx * ry
        }

        let n = points.count
        let degreesOfFreedom = Double(n - 2)
        let speed = hypot(vx, vy)

        var varianceSpeed = 0.0
        if degreesOfFreedom > 0 {
            let varianceX = max(0, rssX / degreesOfFreedom) / sxx
            let varianceY = max(0, rssY / degreesOfFreedom) / sxx
            let covariance = (rssXY / degreesOfFreedom) / sxx
            if speed * speed > 1e-9 {
                varianceSpeed = (vx * vx * varianceX
                    + vy * vy * varianceY
                    + 2 * vx * vy * covariance) / (speed * speed)
            } else {
                varianceSpeed = varianceX + varianceY
            }
        }

        let standardError = sqrt(max(0, varianceSpeed))
        guard speed.isFinite, standardError.isFinite else { return nil }

        return Fit(
            n: n,
            weights: weights,
            meanT: meanT,
            meanX: meanX,
            meanY: meanY,
            sxx: sxx,
            vx: vx,
            vy: vy,
            rss0: rss0,
            rss1: rss1,
            rssX: rssX,
            rssY: rssY,
            rssXY: rssXY,
            residualX: residualX,
            residualY: residualY,
            speed: speed,
            standardError: standardError
        )
    }

    private static func baseAnalysis(
        used: [MotionPoint],
        fit: Fit,
        span: Double,
        medianAccuracy: Double,
        removedID: Int?
    ) -> WindowAnalysis {
        let resolution = 1.25 * medianAccuracy / max(span, 0.001)
        let margin = fit.speed - 2 * fit.standardError - resolution
        return WindowAnalysis(
            verdict: .stabilizing,
            reason: "undetermined",
            sampleIDs: used.map(\.id),
            usedCount: used.count,
            span: span,
            speed: fit.speed,
            standardError: fit.standardError,
            resolution: resolution,
            margin: margin,
            rss0: fit.rss0,
            rss1: fit.rss1,
            fStatistic: nil,
            medianAccuracy: medianAccuracy,
            removedOutlierID: removedID,
            isModelConsistent: true,
            usedInvariantTolerance: 0
        )
    }

    private static func applyMovement(
        _ analysis: inout WindowAnalysis,
        constants: MotionConstants,
        reason: String
    ) {
        if analysis.margin > constants.movingEvidenceMinimum {
            analysis.verdict = .moving
            analysis.reason = reason
        } else {
            analysis.verdict = .stabilizing
            analysis.reason = "insufficientMovementMargin"
        }
    }

    private static func hasGap(_ points: [MotionPoint], maxGap: Double) -> Bool {
        guard points.count > 1 else { return false }
        for index in 1..<points.count {
            if points[index].t - points[index - 1].t > maxGap {
                return true
            }
        }
        return false
    }

    public static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    // MARK: - Geometry

    public static func haversine(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let deltaPhi = (latitude2 - latitude1) * .pi / 180
        let deltaLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }
}
