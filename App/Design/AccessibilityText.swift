import Foundation

/// VoiceOver wording shared by the dashboard.
///
/// Kept free of SwiftUI so the Foundation test harness can verify the strings
/// and the unit handling without a UI host.
enum AccessibilityText {
    static let speedLabel = "Speed"
    static let noReading = "No current reading"

    static func speedValue(_ value: String, spokenUnit: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "—" else { return noReading }
        let unit = spokenUnit.trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? trimmed : "\(trimmed) \(unit)"
    }

    /// The dial reports the measurement and the state it is in, so VoiceOver
    /// users learn "searching" or "low accuracy" without seeing the caption.
    static func gaugeValue(_ value: String, spokenUnit: String, stateCaption: String) -> String {
        let reading = speedValue(value, spokenUnit: spokenUnit)
        let caption = stateCaption.trimmingCharacters(in: .whitespaces)
        guard reading != noReading, !caption.isEmpty else { return reading }
        return "\(reading), \(caption.lowercased())"
    }

    static func metric(title: String, value: String, unit: String, isApproximate: Bool) -> String {
        var parts = [title]
        if isApproximate { parts.append("approximately") }
        parts.append(value)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        if !trimmedUnit.isEmpty { parts.append(trimmedUnit) }
        return parts.joined(separator: " ")
    }
}
