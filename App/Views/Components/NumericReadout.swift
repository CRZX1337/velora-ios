import SwiftUI

/// The one place a rolling number is drawn.
///
/// The trip duration and the speed readout both come through here, so the two
/// cannot drift apart. Three rules are enforced in one place:
///
/// 1. The roll is keyed on the *number*, not on the formatted string. A string
///    is a presentation detail; only the number can be interpolated from what is
///    currently on screen.
/// 2. The content transition carries that same number, so SwiftUI knows where
///    the digits are and can continue a roll that is still in flight instead of
///    starting over or cutting.
/// 3. The text keeps one identity for the lifetime of the readout. There is no
///    conditional around it, so no branch swap can reset the transition.
///
/// Nothing here runs per frame: a readout whose number does not change does no
/// work at all.
struct NumericReadout: View {
    /// The number the readout shows, in display units: whole seconds for a
    /// duration, whole or fractional units for a measurement.
    let value: Double
    /// What the slot renders, formatted from `value`.
    let text: String
    let font: Font
    var tracking: CGFloat = 0
    /// Demo playback feeds samples many times per second and Reduce Motion
    /// removes travel; both keep the value and drop the roll.
    var animationsEnabled = true
    /// Shrinks the text inside a card instead of truncating it at large Dynamic
    /// Type sizes.
    var minimumScaleFactor: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool {
        animationsEnabled && !reduceMotion
    }

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .tracking(tracking)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .contentTransition(.numericText(value: value))
            .animation(animates ? VELORAMotion.readout : nil, value: value)
    }
}
