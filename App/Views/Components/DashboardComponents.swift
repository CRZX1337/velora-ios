import Foundation
import SwiftUI

struct GPSStatusPresentation {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    static func make(
        for status: GPSStatus,
        tripState: TripState,
        startUpdatesCallCount: Int
    ) -> GPSStatusPresentation {
        switch status {
        case .servicesDisabled, .permissionRequired, .permissionDenied, .error:
            return base(for: status)
        default:
            break
        }

        if tripState == .idle, startUpdatesCallCount == 0 {
            return GPSStatusPresentation(
                title: "GPS Ready",
                subtitle: "Start a trip to enable location updates.",
                symbol: "location",
                tint: AppTheme.Colors.textSecondary
            )
        }

        if tripState == .paused {
            return GPSStatusPresentation(
                title: "Trip Paused",
                subtitle: "Location updates are paused.",
                symbol: "pause.circle",
                tint: AppTheme.Colors.warning
            )
        }

        return base(for: status)
    }

    private static func base(for status: GPSStatus) -> GPSStatusPresentation {
        switch status {
        case .servicesDisabled:
            return GPSStatusPresentation(
                title: "Location Services Off",
                subtitle: "Enable Location Services in the device settings.",
                symbol: "location.slash",
                tint: AppTheme.Colors.warning
            )
        case .permissionRequired:
            return GPSStatusPresentation(
                title: "Location Access Required",
                subtitle: "Your location is used only while a trip is active.",
                symbol: "location",
                tint: AppTheme.Colors.accent
            )
        case .permissionDenied:
            return GPSStatusPresentation(
                title: "Location Access Denied",
                subtitle: "Allow location access in iOS Settings.",
                symbol: "location.slash",
                tint: AppTheme.Colors.warning
            )
        case .starting:
            return GPSStatusPresentation(
                title: "Starting Location Services",
                subtitle: "Initializing CoreLocation.",
                symbol: "location",
                tint: AppTheme.Colors.textSecondary
            )
        case .waitingForFirstFix:
            return GPSStatusPresentation(
                title: "No Location Fix Yet",
                subtitle: "CoreLocation is running; waiting for the first GPS fix.",
                symbol: "location",
                tint: AppTheme.Colors.warning
            )
        case .inaccurate(let accuracy):
            return GPSStatusPresentation(
                title: "Location Available, Low Accuracy",
                subtitle: "Accuracy \(formattedAccuracy(accuracy)) · requires ≤ 35 m.",
                symbol: "location",
                tint: AppTheme.Colors.warning
            )
        case .stale(let age):
            return GPSStatusPresentation(
                title: "Location Reading Stale",
                subtitle: "Last reading \(Int(max(0, age).rounded())) s ago.",
                symbol: "clock",
                tint: AppTheme.Colors.warning
            )
        case .error(let code, let description):
            return GPSStatusPresentation(
                title: "GPS Error",
                subtitle: "Code \(code): \(description)",
                symbol: "exclamationmark.triangle",
                tint: AppTheme.Colors.danger
            )
        case .ready(let accuracy):
            let detail = formattedAccuracy(accuracy)
            return GPSStatusPresentation(
                title: "GPS Active",
                subtitle: detail == "—"
                    ? "Location is processed on device."
                    : "Accuracy \(detail) · on device",
                symbol: "location.fill",
                tint: AppTheme.Colors.success
            )
        }
    }

    private static func formattedAccuracy(_ accuracy: Double?) -> String {
        guard let accuracy, accuracy.isFinite, accuracy >= 0 else { return "—" }
        return "±\(String(format: "%.1f", accuracy)) m"
    }
}

struct MotionPresentation {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    static func make(
        state: MotionVerdict,
        tripState: TripState,
        statusConflict: Bool,
        decisionConflict: Bool,
        hasGaps: Bool
    ) -> MotionPresentation {
        if statusConflict || decisionConflict {
            return MotionPresentation(
                title: "Conflicting Signals",
                subtitle: "Position, segment and native readings disagree. Distance stays locked.",
                symbol: "exclamationmark.triangle",
                tint: AppTheme.Colors.warning
            )
        }

        if tripState != .running {
            return MotionPresentation(
                title: tripState == .paused ? "Paused" : "Ready",
                subtitle: tripState == .paused
                    ? "Distance coverage is frozen."
                    : "Start a trip to evaluate movement.",
                symbol: tripState == .paused ? "pause.circle" : "circle.dashed",
                tint: AppTheme.Colors.textSecondary
            )
        }

        switch state {
        case .moving:
            return MotionPresentation(
                title: "Movement Confirmed",
                subtitle: hasGaps
                    ? "Distance is being recorded; some segments remain unconfirmed."
                    : "Distance is recorded from confirmed positions.",
                symbol: "arrow.up.right",
                tint: AppTheme.Colors.success
            )
        case .stationary:
            return MotionPresentation(
                title: "Stationary",
                subtitle: "Confirmed by position data; no distance is added.",
                symbol: "pause.fill",
                tint: AppTheme.Colors.textSecondary
            )
        case .stabilizing:
            return MotionPresentation(
                title: "Checking Movement",
                subtitle: "GPS evidence is not yet sufficient for a decision.",
                symbol: "waveform.path",
                tint: AppTheme.Colors.warning
            )
        }
    }
}

struct DashboardHeader: View {
    let state: TripState
    let isDemo: Bool
    let demoDetail: String?
    let onOpenSettings: () -> Void

    private var stateTitle: String {
        switch state {
        case .idle: "Ready"
        case .running: "Trip Active"
        case .paused: "Paused"
        }
    }

    private var stateColor: Color {
        switch state {
        case .idle: AppTheme.Colors.textTertiary
        case .running: AppTheme.Colors.success
        case .paused: AppTheme.Colors.warning
        }
    }

    private var stateSymbol: String {
        switch state {
        case .idle: "circle"
        case .running: "record.circle"
        case .paused: "pause.circle"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 10) {
                Text("VELORA")
                    .font(AppTheme.Typography.eyebrow)
                    .tracking(3.6)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 7) {
                    Image(systemName: stateSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(stateColor)
                        .contentTransition(.symbolEffect(.replace))

                    Text(stateTitle.uppercased())
                        .font(AppTheme.Typography.stateChip)
                        .tracking(1.0)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(AppTheme.Colors.surface)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.Colors.hairline, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Trip status: \(stateTitle)")

                if isDemo {
                    HStack(spacing: 6) {
                        Image(systemName: "testtube.2")
                            .font(.system(size: 10, weight: .bold))

                        Text(demoDetail.map { "DEMO MODE · \($0)" } ?? "DEMO MODE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(AppTheme.Colors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(AppTheme.Colors.warning.opacity(0.12)))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(AppTheme.Colors.warning.opacity(0.35), lineWidth: 1)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Demo mode. Displayed data is simulated.")
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: AppTheme.Control.icon, height: AppTheme.Control.icon)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
        }
    }
}

/// One status surface for movement and GPS. The icon chip carries the colour,
/// the text stays primary; a state never relies on hue alone.
struct StatusCard: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    var actionTitle: String?
    var actionHint: String?
    var action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stacksContent: Bool {
        dynamicTypeSize.isAccessibilitySize && action != nil
    }

    var body: some View {
        Group {
            if stacksContent {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        iconChip
                        textBlock
                    }

                    actionButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                    iconChip
                    textBlock
                    Spacer(minLength: AppTheme.Spacing.xxs)
                    actionButton
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .veloraSurface(.card, padding: 0)
    }

    private var iconChip: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.12), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTheme.Typography.statusTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(detail)
                .font(AppTheme.Typography.statusDetail)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(action: action) {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .frame(minHeight: AppTheme.Control.compact)
                    .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(PressableButtonStyle(isEnabled: !reduceMotion))
            .accessibilityLabel(actionTitle)
            .accessibilityHint(actionHint ?? "")
        }
    }
}

struct MotionStatusCard: View {
    let presentation: MotionPresentation

    var body: some View {
        StatusCard(
            symbol: presentation.symbol,
            title: presentation.title,
            detail: presentation.subtitle,
            tint: presentation.tint
        )
    }
}

/// GPS state as a quiet status line. Permission is requested from the trip
/// controls, so this card never carries a permission action of its own.
struct GPSStatusCard: View {
    let presentation: GPSStatusPresentation

    var body: some View {
        StatusCard(
            symbol: presentation.symbol,
            title: presentation.title,
            detail: presentation.subtitle,
            tint: presentation.tint
        )
    }
}

struct MetricCard: View {
    let title: String
    /// The number the roll is keyed on, in display units and at the precision
    /// `value` shows, so the animation is armed by a measurement rather than by
    /// a formatted string.
    let numericValue: Double
    let value: String
    let unit: String
    let symbol: String
    var isApproximate = false
    var animationsEnabled = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacksUnit: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(AppTheme.Typography.label)
                    .tracking(1.0)

                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.Colors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if isApproximate {
                    Text("≈")
                        .font(AppTheme.Typography.metricValue)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                NumericReadout(
                    value: numericValue,
                    text: value,
                    font: AppTheme.Typography.metricValue,
                    animationsEnabled: animationsEnabled,
                    minimumScaleFactor: 0.72
                )
                .foregroundStyle(AppTheme.Colors.textPrimary)

                if !unit.isEmpty, !stacksUnit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            if !unit.isEmpty, stacksUnit {
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .veloraSurface(.card, padding: 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.metric(title: title, value: value, unit: unit, isApproximate: isApproximate)
        )
    }
}

struct MetricGrid: View {
    let maximumSpeedMetersPerSecond: Double
    let averageSpeedMetersPerSecond: Double
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let unit: SpeedUnit
    let hasCoverageGaps: Bool
    var animationsEnabled = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
            ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
            MetricCard(
                title: "MAX",
                numericValue: NumericDisplay.anchor(
                    unit.speed(fromMetersPerSecond: maximumSpeedMetersPerSecond),
                    fractionDigits: 0
                ),
                value: unit.formattedSpeed(maximumSpeedMetersPerSecond),
                unit: unit.title,
                symbol: "arrow.up.right",
                animationsEnabled: animationsEnabled
            )

            MetricCard(
                title: "AVERAGE",
                numericValue: NumericDisplay.anchor(
                    unit.speed(fromMetersPerSecond: averageSpeedMetersPerSecond),
                    fractionDigits: 0
                ),
                value: unit.formattedSpeed(averageSpeedMetersPerSecond),
                unit: unit.title,
                symbol: "waveform.path",
                isApproximate: hasCoverageGaps,
                animationsEnabled: animationsEnabled
            )

            MetricCard(
                title: "DISTANCE",
                numericValue: NumericDisplay.anchor(
                    unit.distance(fromMeters: distanceMeters),
                    fractionDigits: 2
                ),
                value: unit.formattedDistance(distanceMeters),
                unit: unit.distanceTitle,
                symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                animationsEnabled: animationsEnabled
            )

            MetricCard(
                title: "TRIP TIME",
                // Whole seconds: one text change per second, and therefore
                // exactly one roll per second.
                numericValue: Double(max(0, Int(elapsedSeconds))),
                value: NumericDisplay.duration(seconds: elapsedSeconds),
                unit: "",
                symbol: "clock",
                animationsEnabled: animationsEnabled
            )
        }
    }
}

/// Trip controls. They keep their equality check, so a high-frequency GPS
/// sample cannot rebuild them, while a state change still animates once.
struct DriveControls: View, Equatable {
    let state: TripState
    /// Mirrors Reduce Motion and is part of the equality check, so toggling the
    /// setting still refreshes the controls while high-frequency trip samples
    /// do not rebuild them.
    let animationsEnabled: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onReset: () -> Void

    private let controlSize = AppTheme.Control.primary
    private let controlSpacing: CGFloat = 12

    static func == (lhs: DriveControls, rhs: DriveControls) -> Bool {
        lhs.state == rhs.state && lhs.animationsEnabled == rhs.animationsEnabled
    }

    private func perform(_ action: @escaping () -> Void) {
        withAnimation(animationsEnabled ? VELORAMotion.selection : nil) {
            action()
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: controlSpacing) {
            HStack(spacing: controlSpacing) {
                if state == .idle {
                    primaryControl(
                        title: "Start Trip",
                        symbol: "play.fill",
                        action: { perform(onStart) }
                    )
                } else {
                    Button {
                        perform(onReset)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(width: controlSize, height: controlSize)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Reset Trip")

                    primaryControl(
                        title: state == .running ? "Pause" : "Resume",
                        symbol: state == .running ? "pause.fill" : "play.fill",
                        action: {
                            perform(state == .running ? onPause : onResume)
                        }
                    )
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func primaryControl(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: controlSize)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(AppTheme.Colors.accent)
    }
}
