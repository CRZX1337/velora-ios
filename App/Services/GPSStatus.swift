import Foundation

enum GPSStatus: Equatable {
    case servicesDisabled
    case permissionRequired
    case permissionDenied
    case starting
    case waitingForFirstFix
    case inaccurate(accuracy: Double?)
    case stale(age: TimeInterval)
    case error(code: Int, description: String)
    case ready(accuracy: Double?)
}

/// Pure classification of a CoreLocation reading.
///
/// `LocationService` owns the `CLLocationManager` and feeds the raw values in
/// here, but the decision table itself has no CoreLocation dependency, so the
/// Foundation test harness can cover every branch without hardware.
enum GPSStatusResolution {
    /// A reading older than this counts as stale.
    static let staleAfter: TimeInterval = 5
    /// Readings above this horizontal accuracy are not a usable fix.
    static let accuracyThreshold: Double = 35

    private static func isUsableAccuracy(_ accuracy: Double) -> Bool {
        accuracy.isFinite && accuracy > 0
    }

    static func status(
        measurementAge: TimeInterval?,
        measurementAccuracy: Double?,
        reportedAccuracy: Double?,
        callbackAge: TimeInterval?
    ) -> GPSStatus {
        // A measurement only counts when it carries a sane accuracy. Accuracy is
        // checked before freshness: a fresh but coarse fix must not be reported
        // as ready.
        if let measurementAge,
           let measurementAccuracy,
           isUsableAccuracy(measurementAccuracy) {
            guard measurementAge <= staleAfter else {
                return .stale(age: measurementAge)
            }
            return measurementAccuracy <= accuracyThreshold
                ? .ready(accuracy: measurementAccuracy)
                : .inaccurate(accuracy: measurementAccuracy)
        }

        // Without a usable measurement only an implausible reported accuracy is
        // still worth surfacing as low accuracy.
        if let reportedAccuracy,
           reportedAccuracy.isFinite,
           reportedAccuracy > accuracyThreshold {
            return .inaccurate(accuracy: reportedAccuracy)
        }

        guard let callbackAge else { return .waitingForFirstFix }
        return callbackAge > staleAfter ? .stale(age: callbackAge) : .waitingForFirstFix
    }
}
