import Foundation

// MARK: - Profiles

/// Deterministic driving programs for the demo source. Foundation-only so the
/// Windows harness can exercise every profile without CoreLocation.
enum DemoDriveProfile: String, CaseIterable, Identifiable, Sendable {
    case city
    case highway
    case autobahn
    case mixed
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .city: "City"
        case .highway: "Highway"
        case .autobahn: "Autobahn"
        case .mixed: "Mixed"
        case .custom: "Custom"
        }
    }

    var summary: String {
        switch self {
        case .city:
            "Stop-and-go traffic with repeated traffic-light stops between 0 and 50 km/h."
        case .highway:
            "Smooth 80–130 km/h cruising with occasional slowdowns."
        case .autobahn:
            "Long 100–160 km/h phases with deliberate acceleration and deceleration."
        case .mixed:
            "City, country road and autobahn combined, including full stops."
        case .custom:
            "A manual target speed, acceleration rate and duration."
        }
    }

    var symbolName: String {
        switch self {
        case .city: "building.2"
        case .highway: "road.lanes"
        case .autobahn: "speedometer"
        case .mixed: "map"
        case .custom: "slider.horizontal.3"
        }
    }

    var isCyclic: Bool { self != .custom }
}

enum DemoSignalMode: String, CaseIterable, Identifiable, Sendable {
    case live
    case outage
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live Fixes"
        case .outage: "Signal Outage"
        case .error: "Signal Lost"
        }
    }

    var summary: String {
        switch self {
        case .live: "Synthetic fixes reach the pipeline at the selected accuracy."
        case .outage: "No fixes arrive; the dashboard shows a stale reading, then recovers."
        case .error: "CoreLocation-style failure is reported until the signal is restored."
        }
    }
}

// MARK: - Configuration

struct DemoDriveConfiguration: Equatable, Sendable {
    static let supportedRates: [Double] = [0.5, 1, 2, 5, 10]

    var profile: DemoDriveProfile = .city
    var rate: Double = 1
    var accuracyMeters: Double = 6
    /// Simulated seconds before the first fix arrives. Keeps the
    /// "waiting for first fix" state observable.
    var initialFixDelay: TimeInterval = 2
    var signalMode: DemoSignalMode = .live

    var customTargetKPH: Double = 80
    var customAccelerationKPHPerSecond: Double = 9
    var customDuration: TimeInterval = 60

    var effectiveRate: Double {
        guard rate.isFinite else { return 1 }
        return min(max(rate, 0.5), 10)
    }

    var effectiveAccuracy: Double {
        guard accuracyMeters.isFinite else { return 6 }
        return min(max(accuracyMeters, 1), 500)
    }
}

// MARK: - Timeline

struct DemoDriveSegment: Equatable, Sendable {
    let duration: TimeInterval
    let fromKPH: Double
    let toKPH: Double

    func speed(at offset: TimeInterval) -> Double {
        guard duration > 0 else { return toKPH }
        let progress = min(max(offset / duration, 0), 1)
        return fromKPH + (toKPH - fromKPH) * progress
    }
}

struct DemoDriveSample: Equatable, Sendable {
    let elapsed: TimeInterval
    let speedKPH: Double
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let hasFix: Bool
    let signalMode: DemoSignalMode
}

/// A deterministic, replayable drive. Advancing by simulated seconds produces
/// the same speed, odometer and position every time; the controller is the only
/// place where wall-clock timing and CoreLocation objects are involved.
struct DemoDriveTimeline {
    var configuration: DemoDriveConfiguration
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var latitude: Double = 52.520008
    private(set) var longitude: Double = 13.404954
    private(set) var currentSpeedKPH: Double = 0
    private var manualTargetKPH: Double?
    private let segments: [DemoDriveSegment]
    private let cycleDuration: TimeInterval

    init(configuration: DemoDriveConfiguration) {
        self.configuration = configuration
        self.segments = Self.segments(for: configuration.profile)
        self.cycleDuration = segments.reduce(0) { $0 + $1.duration }
    }

    /// Advances the simulated clock by `realDelta * rate` seconds.
    @discardableResult
    mutating func advance(by realDelta: TimeInterval) -> DemoDriveSample {
        let delta = max(0, realDelta) * configuration.effectiveRate
        let previousSpeed = currentSpeedKPH
        elapsed += delta

        let nextSpeed: Double
        switch configuration.profile {
        case .custom:
            let desired: Double
            if let manualTargetKPH {
                desired = manualTargetKPH
            } else if elapsed >= configuration.customDuration {
                desired = 0
            } else {
                desired = configuration.customTargetKPH
            }
            let acceleration = max(configuration.customAccelerationKPHPerSecond, 0.5)
            nextSpeed = Self.move(previousSpeed, toward: desired, by: acceleration * delta)
        default:
            nextSpeed = cycleSpeed(at: elapsed)
        }

        currentSpeedKPH = nextSpeed
        let metres = max(0, (previousSpeed + nextSpeed) / 2 / 3.6 * delta)
        distanceMeters += metres
        advancePosition(by: metres)

        let hasFix = elapsed >= configuration.initialFixDelay
            && configuration.signalMode == .live

        return DemoDriveSample(
            elapsed: elapsed,
            speedKPH: nextSpeed,
            distanceMeters: distanceMeters,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: configuration.effectiveAccuracy,
            hasFix: hasFix,
            signalMode: configuration.signalMode
        )
    }

    mutating func reset() {
        elapsed = 0
        distanceMeters = 0
        latitude = 52.520008
        longitude = 13.404954
        currentSpeedKPH = 0
        manualTargetKPH = nil
    }

    /// `nil` returns the custom profile to its configured target.
    mutating func setManualTarget(_ speedKPH: Double?) {
        guard let speedKPH else {
            manualTargetKPH = nil
            return
        }
        manualTargetKPH = min(max(speedKPH, 0), 300)
    }

    var isManualStillness: Bool {
        manualTargetKPH == 0
    }

    // MARK: - Segment programs

    private func cycleSpeed(at time: TimeInterval) -> Double {
        guard !segments.isEmpty, cycleDuration > 0 else { return 0 }
        var offset = time.truncatingRemainder(dividingBy: cycleDuration)
        if offset < 0 { offset += cycleDuration }
        for segment in segments {
            if offset < segment.duration {
                return segment.speed(at: offset)
            }
            offset -= segment.duration
        }
        return segments.last?.toKPH ?? 0
    }

    private static func move(_ value: Double, toward target: Double, by maximumDelta: Double) -> Double {
        if value < target {
            return min(target, value + maximumDelta)
        }
        return max(target, value - maximumDelta)
    }

    private mutating func advancePosition(by metres: Double) {
        guard metres > 0 else { return }
        let heading = 38.0 * Double.pi / 180
        let metresPerDegreeLatitude = 111_320.0
        let cosine = max(0.2, cos(latitude * Double.pi / 180))
        latitude = min(max(latitude + metres * cos(heading) / metresPerDegreeLatitude, -85), 85)
        longitude += metres * sin(heading) / (metresPerDegreeLatitude * cosine)
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
    }

    private static func segments(for profile: DemoDriveProfile) -> [DemoDriveSegment] {
        switch profile {
        case .city:
            [
                .init(duration: 10, fromKPH: 0, toKPH: 50),
                .init(duration: 8, fromKPH: 50, toKPH: 50),
                .init(duration: 5, fromKPH: 50, toKPH: 20),
                .init(duration: 4, fromKPH: 20, toKPH: 20),
                .init(duration: 5, fromKPH: 20, toKPH: 0),
                .init(duration: 8, fromKPH: 0, toKPH: 0),
                .init(duration: 8, fromKPH: 0, toKPH: 35),
                .init(duration: 5, fromKPH: 35, toKPH: 45),
                .init(duration: 6, fromKPH: 45, toKPH: 45),
                .init(duration: 6, fromKPH: 45, toKPH: 0),
                .init(duration: 5, fromKPH: 0, toKPH: 0)
            ]
        case .highway:
            [
                .init(duration: 14, fromKPH: 0, toKPH: 100),
                .init(duration: 5, fromKPH: 100, toKPH: 80),
                .init(duration: 12, fromKPH: 80, toKPH: 130),
                .init(duration: 15, fromKPH: 130, toKPH: 130),
                .init(duration: 8, fromKPH: 130, toKPH: 95),
                .init(duration: 10, fromKPH: 95, toKPH: 120),
                .init(duration: 15, fromKPH: 120, toKPH: 120),
                .init(duration: 6, fromKPH: 120, toKPH: 85),
                .init(duration: 5, fromKPH: 85, toKPH: 85)
            ]
        case .autobahn:
            [
                .init(duration: 16, fromKPH: 0, toKPH: 120),
                .init(duration: 15, fromKPH: 120, toKPH: 160),
                .init(duration: 30, fromKPH: 160, toKPH: 160),
                .init(duration: 12, fromKPH: 160, toKPH: 100),
                .init(duration: 8, fromKPH: 100, toKPH: 100),
                .init(duration: 14, fromKPH: 100, toKPH: 150),
                .init(duration: 15, fromKPH: 150, toKPH: 150),
                .init(duration: 6, fromKPH: 150, toKPH: 110)
            ]
        case .mixed:
            [
                .init(duration: 10, fromKPH: 0, toKPH: 50),
                .init(duration: 8, fromKPH: 50, toKPH: 50),
                .init(duration: 7, fromKPH: 50, toKPH: 0),
                .init(duration: 6, fromKPH: 0, toKPH: 0),
                .init(duration: 10, fromKPH: 0, toKPH: 80),
                .init(duration: 10, fromKPH: 80, toKPH: 80),
                .init(duration: 8, fromKPH: 80, toKPH: 100),
                .init(duration: 10, fromKPH: 100, toKPH: 100),
                .init(duration: 12, fromKPH: 100, toKPH: 130),
                .init(duration: 18, fromKPH: 130, toKPH: 130),
                .init(duration: 10, fromKPH: 130, toKPH: 60),
                .init(duration: 8, fromKPH: 60, toKPH: 0),
                .init(duration: 8, fromKPH: 0, toKPH: 0)
            ]
        case .custom:
            []
        }
    }
}
