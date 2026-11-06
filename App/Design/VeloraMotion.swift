import SwiftUI

/// One motion vocabulary for the whole app.
///
/// Every authored animation comes from here, so sibling controls cannot drift
/// apart: tap-driven motion is critically damped (`.smooth`/`.snappy`), nothing
/// bounces without momentum, and no animation outruns the value it presents.
enum VELORAMotion {
    /// The dial and its indicator trail the measured value.
    static let gauge = Animation.smooth(duration: 0.34)
    /// Digit changes roll instead of cutting.
    static let readout = Animation.snappy(duration: 0.22)
    /// Press feedback on non-glass controls.
    static let press = Animation.snappy(duration: 0.16)
    /// Selection changes (units, segmented pickers).
    static let selection = Animation.smooth(duration: 0.24)
    /// Sheet and navigation chrome.
    static let sheet = Animation.smooth(duration: 0.36)

    /// Reduce Motion substitutes a still frame instead of removing feedback:
    /// the value still changes, it just arrives without travel.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// A press state that scales the label in place. Used where the native glass
/// button styles do not apply, for example compact chips inside a card.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? scale : 1)
            .animation(isEnabled ? VELORAMotion.press : nil, value: configuration.isPressed)
    }
}


