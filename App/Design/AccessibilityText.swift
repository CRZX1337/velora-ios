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

    static func metric(title: String, value: String, unit: String, isApproximate: Bool) -> String {
        var parts = [title]
        if isApproximate { parts.append("approximately") }
        parts.append(value)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        if !trimmedUnit.isEmpty { parts.append(trimmedUnit) }
        return parts.joined(separator: " ")
    }
}
