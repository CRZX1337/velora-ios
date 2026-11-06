import Foundation

/// Presentation maths for rolling numeric readouts.
///
/// A digit roll is armed by a *number*, never by the string it is formatted
/// into. Both helpers exist so the two can never disagree: the string is built
/// from the anchor, and the anchor moves exactly when the string does — once per
/// change, never in between and never twice for one change.
enum NumericDisplay {
    /// The trip duration as `HH:MM:SS`, in whole seconds.
    ///
    /// Truncating to whole seconds is what makes every second exactly one text
    /// change and therefore exactly one roll, independent of how often the
    /// measurement publishes in between.
    static func duration(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(
            format: "%02d:%02d:%02d",
            total / 3_600,
            (total / 60) % 60,
            total % 60
        )
    }

    /// The anchor for a formatted value: the number rounded to the precision the
    /// string actually shows, in display units.
    ///
    /// A speed of `62.4` km/h is shown as `62`, so its anchor is `62`; a distance
    /// of `1.234` km is shown as `1.23`, so its anchor is `1.23`.
    static func anchor(_ value: Double, fractionDigits: Int) -> Double {
        guard value.isFinite else { return 0 }
        let factor = pow(10, Double(max(0, fractionDigits)))
        return (max(0, value) * factor).rounded() / factor
    }
}
