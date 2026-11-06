import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable {
    case kilometersPerHour
    case milesPerHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilometersPerHour: "km/h"
        case .milesPerHour: "mph"
        }
    }

    /// Spelled-out unit name for VoiceOver; "km/h" is otherwise read letter by
    /// letter.
    var spokenTitle: String {
        switch self {
        case .kilometersPerHour: "kilometers per hour"
        case .milesPerHour: "miles per hour"
        }
    }

    func speed(fromMetersPerSecond value: Double) -> Double {
        switch self {
        case .kilometersPerHour: value * 3.6
        case .milesPerHour: value * 2.236_936_292_054_4
        }
    }

    func distance(fromMeters value: Double) -> Double {
        switch self {
        case .kilometersPerHour: value / 1_000
        case .milesPerHour: value / 1_609.344
        }
    }

    var distanceTitle: String {
        switch self {
        case .kilometersPerHour: "km"
        case .milesPerHour: "mi"
        }
    }

    func formattedSpeed(_ metersPerSecond: Double, fractionDigits: Int = 0) -> String {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "—" }
        return speed(fromMetersPerSecond: metersPerSecond)
            .formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    func formattedDistance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "0.00" }
        return distance(fromMeters: meters).formatted(.number.precision(.fractionLength(2)))
    }
}
