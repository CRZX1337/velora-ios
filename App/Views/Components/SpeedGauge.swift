import Foundation
import SwiftUI

struct GaugeScale: Equatable {
    let maximum: Double
    let labels: [Double]

    static func make(for unit: SpeedUnit) -> GaugeScale {
        switch unit {
        case .kilometersPerHour:
            return GaugeScale(maximum: 320, labels: [0, 80, 160, 240, 320])
        case .milesPerHour:
            return GaugeScale(maximum: 200, labels: [0, 50, 100, 150, 200])
        }
    }
}

/// What the dial communicates right now. Every case is derived from CoreLocation
/// and the trip state; nothing here invents a measurement or a GPS lock.
enum GaugeState: Equatable {
    case inactive
    case searching
    case live
    case degraded
    case paused

    var caption: String {
        switch self {
        case .inactive: "NOT STARTED"
        case .searching: "SEARCHING"
        case .live: "GPS ACTIVE"
        case .degraded: "LOW ACCURACY"
        case .paused: "PAUSED"
        }
    }

    var symbol: String {
        switch self {
        case .inactive: "circle.dashed"
        case .searching: "location"
        case .live: "location.fill"
        case .degraded: "exclamationmark.triangle"
        case .paused: "pause.fill"
        }
    }

    var tint: Color {
        switch self {
        case .inactive: AppTheme.Colors.textTertiary
        case .searching: AppTheme.Colors.textSecondary
        case .live: AppTheme.Colors.success
        case .degraded, .paused: AppTheme.Colors.warning
        }
    }

    static func make(status: GPSStatus, tripState: TripState, hasReading: Bool) -> GaugeState {
        if tripState == .paused { return .paused }

        switch status {
        case .servicesDisabled, .permissionDenied, .error:
            return .inactive
        case .inaccurate, .stale:
            return .degraded
        case .ready:
            return hasReading ? .live : .searching
        case .permissionRequired, .starting, .waitingForFirstFix:
            return tripState == .idle && !hasReading ? .inactive : .searching
        }
    }
}

struct SpeedGauge: View {
    /// The measured value in the displayed unit. Only the dial's presentation
    /// interpolates; the engine, recorder and session never see this view.
    let speed: Double
    let valueText: String
    let unitTitle: String
    let unitSpokenTitle: String
    let state: GaugeState
    let diameter: CGFloat
    let scale: GaugeScale
    /// Simulated fixes arrive many times per second, so the digits settle
    /// instead of rolling on every synthetic sample.
    var isSimulated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var unitScale: CGFloat = 1

    private let startAngle: Double = 135
    private let sweep: Double = 270
    private let labelCount = 28

    private var clampedProgress: Double {
        min(max(speed / scale.maximum, 0), 1)
    }

    private var ringWidth: CGFloat {
        max(11, diameter * 0.036)
    }

    private var isPlaceholder: Bool {
        valueText == "—"
    }

    private var speedFontSize: CGFloat {
        let base = isPlaceholder ? diameter * 0.10 * typeScale : diameter * 0.285 * typeScale
        return min(base, diameter * (isPlaceholder ? 0.15 : 0.31))
    }

    private var unitFontSize: CGFloat {
        min(diameter * 0.050 * unitScale, diameter * 0.072)
    }

    private var arcColor: Color {
        switch state {
        case .degraded, .paused: AppTheme.Colors.warning
        case .inactive, .searching, .live: AppTheme.Colors.gaugeProgress
        }
    }

    var body: some View {
        ZStack {
            disc
            track
            progressArc
            ticks
            innerHairline
            indicator
            readout
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.speedLabel)
        .accessibilityValue(
            AccessibilityText.gaugeValue(valueText, spokenUnit: unitSpokenTitle, stateCaption: state.caption)
        )
    }

    // MARK: - Layers

    private var disc: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [AppTheme.Colors.gaugeDisc, .clear],
                    center: UnitPoint(x: 0.5, y: 0.34),
                    startRadius: 0,
                    endRadius: diameter * 0.47
                )
            )
            .padding(ringWidth * 1.6)
            .overlay {
                Circle()
                    .strokeBorder(AppTheme.Colors.hairline, lineWidth: 1)
                    .padding(ringWidth * 1.6)
            }
            .allowsHitTesting(false)
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: sweep / 360)
            .stroke(
                AppTheme.Colors.gaugeTrack,
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
            )
            .rotationEffect(.degrees(startAngle))
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: sweep / 360 * clampedProgress)
            .stroke(
                arcColor,
                style: StrokeStyle(lineWidth: ringWidth * 0.58, lineCap: .round)
            )
            .rotationEffect(.degrees(startAngle))
            .opacity(clampedProgress > 0.001 ? 1 : 0)
            .animation(VELORAMotion.resolve(VELORAMotion.gauge, reduceMotion: reduceMotion), value: clampedProgress)
    }

    /// One dot rides the arc's tip. It rotates rather than being redrawn, so the
    /// movement is a transform and stays cheap while the arc trims.
    private var indicator: some View {
        ZStack {
            Color.clear

            Circle()
                .fill(arcColor)
                .frame(width: ringWidth * 0.92, height: ringWidth * 0.92)
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.Colors.canvas.opacity(0.55), lineWidth: 1)
                }
                .offset(y: -(diameter / 2 - ringWidth * 1.1))
        }
        .opacity(clampedProgress > 0.001 ? 1 : 0)
        .rotationEffect(.degrees(startAngle + sweep * clampedProgress + 90))
        .animation(VELORAMotion.resolve(VELORAMotion.gauge, reduceMotion: reduceMotion), value: clampedProgress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var innerHairline: some View {
        Circle()
            .strokeBorder(AppTheme.Colors.hairline, lineWidth: 1)
            .padding(diameter * 0.155)
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text(valueText)
                .font(.system(size: speedFontSize, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .tracking(-1.2)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .contentTransition(
                    isSimulated || reduceMotion ? .identity : .numericText(value: speed)
                )
                .animation(
                    VELORAMotion.resolve(VELORAMotion.readout, reduceMotion: reduceMotion),
                    value: valueText
                )

            Text(unitTitle.uppercased())
                .font(.system(size: unitFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .tracking(2.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)

            statusChip
                .padding(.top, 12)
        }
        .padding(.horizontal, diameter * 0.19)
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol)
                .font(.system(size: 8, weight: .bold))
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: state == .searching && !reduceMotion
                )
                .contentTransition(.symbolEffect(.replace))

            Text(state.caption)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(state.tint.opacity(0.10))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(state.tint.opacity(0.26), lineWidth: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Ticks

    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2
            let tickOuter = outerRadius - ringWidth - 2
            let majorLength = max(9, diameter * 0.030)
            let minorLength = max(4, diameter * 0.015)

            for index in 0...labelCount {
                let fraction = Double(index) / Double(labelCount)
                let angle = Angle.degrees(startAngle + fraction * sweep).radians
                let isMajor = scale.labels.contains { label in
                    abs(label / scale.maximum - fraction) < 0.0015
                }
                let length = isMajor ? majorLength : minorLength
                let inner = tickOuter - length

                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * inner,
                    y: center.y + sin(angle) * inner
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * tickOuter,
                    y: center.y + sin(angle) * tickOuter
                ))

                context.stroke(
                    path,
                    with: .color(isMajor ? AppTheme.Colors.gaugeTickMajor : AppTheme.Colors.gaugeTickMinor),
                    lineWidth: isMajor ? 1.7 : 1
                )
            }

            let labelRadius = outerRadius - ringWidth - majorLength - 16
            let fontSize = max(9, diameter * 0.033)
            for label in scale.labels {
                let fraction = label / scale.maximum
                let angle = Angle.degrees(startAngle + fraction * sweep).radians
                let point = CGPoint(
                    x: center.x + cos(angle) * labelRadius,
                    y: center.y + sin(angle) * labelRadius
                )
                let text = Text("\(Int(label))")
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                context.draw(text, at: point)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
