import CoreLocation
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

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VELORA")
                    .font(AppTheme.Typography.eyebrow)
                    .tracking(3.2)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                HStack(spacing: 7) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)

                    Text(stateTitle.uppercased())
                        .font(.caption2.weight(.semibold))
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
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.Colors.stroke, lineWidth: 1)
                        }
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
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
        }
    }
}

struct MotionStatusCard: View {
    let presentation: MotionPresentation

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(presentation.tint)
                .frame(width: 36, height: 36)
                .background(presentation.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(AppTheme.Typography.statusTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(presentation.subtitle)
                    .font(AppTheme.Typography.statusDetail)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 22, padding: 0)
        .accessibilityElement(children: .combine)
    }
}

struct GPSStatusCard: View {
    let presentation: GPSStatusPresentation
    let authorizationStatus: CLAuthorizationStatus
    let servicesEnabled: Bool
    let showsPermissionAction: Bool
    let onRequestPermission: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacksContent: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var hasAction: Bool {
        showsPermissionAction
            && ((authorizationStatus == .notDetermined && servicesEnabled)
                || authorizationStatus == .denied)
    }

    var body: some View {
        Group {
            if stacksContent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        iconChip
                        textBlock
                    }

                    if hasAction {
                        action
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    iconChip
                    textBlock
                    Spacer(minLength: 4)
                    action
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 22, padding: 0)
    }

    private var iconChip: some View {
        Image(systemName: presentation.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(presentation.tint)
            .frame(width: 36, height: 36)
            .background(presentation.tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.title)
                .font(AppTheme.Typography.statusTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(presentation.subtitle)
                .font(AppTheme.Typography.statusDetail)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var action: some View {
        if !showsPermissionAction {
            EmptyView()
        } else if authorizationStatus == .notDetermined, servicesEnabled {
            Button(action: onRequestPermission) {
                Text("Allow")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel("Allow location access")
            .accessibilityHint("Requests location access while a trip is active.")
        } else if authorizationStatus == .denied {
            Button(action: onOpenSettings) {
                Text("Open")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel("Open iOS Settings")
            .accessibilityHint("Opens the system settings to allow location access.")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var isApproximate = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the unit moves below the value instead of
    /// squeezing both into one line.
    private var stacksUnit: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(AppTheme.Typography.label)
                    .tracking(0.9)

                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.Colors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if isApproximate {
                    Text("≈")
                        .font(AppTheme.Typography.metricValue)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Text(value)
                    .font(AppTheme.Typography.metricValue)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
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
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .appCard(cornerRadius: 22, padding: 13)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One column at accessibility sizes: two narrow cards would truncate the
    /// values instead of letting them grow.
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
                value: unit.formattedSpeed(maximumSpeedMetersPerSecond),
                unit: unit.title,
                symbol: "arrow.up.right"
            )

            MetricCard(
                title: "AVERAGE",
                value: unit.formattedSpeed(averageSpeedMetersPerSecond),
                unit: unit.title,
                symbol: "waveform.path",
                isApproximate: hasCoverageGaps
            )

            MetricCard(
                title: "DISTANCE",
                value: unit.formattedDistance(distanceMeters),
                unit: unit.distanceTitle,
                symbol: "point.bottomleft.forward.to.point.topright.scurvepath"
            )

            MetricCard(
                title: "TRIP TIME",
                value: formattedDuration,
                unit: "",
                symbol: "clock"
            )
        }
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(elapsedSeconds))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }
}

/// A button whose surface is a native Liquid Glass shape. The glass reacts to
/// touch through the platform's own `interactive` behaviour, so the press
/// feedback, the light refraction and the material depth all come from SwiftUI.
struct GlassControlButton<Label: View, BorderShape: Shape>: View {
    let glass: Glass
    let borderShape: BorderShape
    let isInteractive: Bool
    let action: () -> Void
    private let label: Label

    init(
        glass: Glass,
        borderShape: BorderShape,
        isInteractive: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.glass = glass
        self.borderShape = borderShape
        self.isInteractive = isInteractive
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .contentShape(borderShape)
        .glassEffect(glass.interactive(isInteractive), in: borderShape)
    }
}

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

    private let controlSize: CGFloat = 54
    private let controlSpacing: CGFloat = 12

    static func == (lhs: DriveControls, rhs: DriveControls) -> Bool {
        lhs.state == rhs.state && lhs.animationsEnabled == rhs.animationsEnabled
    }

    /// The closures are captured here rather than in the dashboard, so an
    /// equatable render keeps working actions while ignoring new reader values.
    private func perform(_ action: @escaping () -> Void) {
        withAnimation(animationsEnabled ? .snappy(duration: 0.25) : nil) {
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
                    GlassControlButton(
                        glass: .regular.tint(AppTheme.Colors.glassSecondaryTint),
                        borderShape: Circle(),
                        isInteractive: animationsEnabled,
                        action: { perform(onReset) }
                    ) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.glassLabel)
                            .frame(width: controlSize, height: controlSize)
                    }
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
        GlassControlButton(
            glass: .regular.tint(AppTheme.Colors.glassPrimaryTint),
            borderShape: Capsule(),
            isInteractive: animationsEnabled,
            action: action
        ) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.glassLabel)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .frame(height: controlSize)
        }
    }
}
