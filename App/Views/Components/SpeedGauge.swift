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
    /// Display-only curve in meters per second. The number, the arc and the tip
    /// all read this one curve; the authoritative measurement stays in
    /// `SpeedReading` and is never replaced by it.
    let display: SpeedDisplayCurve
    /// Whether the session currently holds a measured reading. The curve carries
    /// the presentation; this only decides whether the dial shows a number.
    let hasReading: Bool
    let unit: SpeedUnit
    let state: GaugeState
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var unitScale: CGFloat = 1

    private let startAngle: Double = 135
    private let sweep: Double = 270
    private let labelCount = 28
    private let framesPerSecond: Double = 60

    // MARK: - Derived

    private var scale: GaugeScale {
        GaugeScale.make(for: unit)
    }

    /// Reduce Motion keeps the measurement and drops the travel: the same value,
    /// drawn as one frame.
    private var drawnDisplay: SpeedDisplayCurve {
        reduceMotion
            ? SpeedDisplayCurve(target: display.target, response: display.response)
            : display
    }

    private var dialIsResting: Bool {
        drawnDisplay.isSettled(at: Date.timeIntervalSinceReferenceDate)
    }

    private var ringWidth: CGFloat {
        max(11, diameter * 0.036)
    }

    /// One size for the digit slot so the unit and caption never shift when the
    /// first fix arrives; the placeholder simply sits smaller in the same slot.
    private var readoutFontSize: CGFloat {
        min(diameter * 0.285 * typeScale, diameter * 0.31)
    }

    private var readoutSlotHeight: CGFloat {
        readoutFontSize * 1.08
    }

    private var placeholderFontSize: CGFloat {
        min(diameter * 0.12 * typeScale, diameter * 0.14)
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
            ticks
            innerHairline
            instrument
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.speedLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        AccessibilityText.gaugeValue(
            hasReading ? unit.formattedSpeed(display.target) : "—",
            spokenUnit: unit.spokenTitle,
            stateCaption: state.caption
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

    private var innerHairline: some View {
        Circle()
            .strokeBorder(AppTheme.Colors.hairline, lineWidth: 1)
            .padding(diameter * 0.155)
    }

    /// Arc, tip and digits are drawn per frame from the same curve, so the dial
    /// is one continuous instrument rather than three animations that can drift
    /// apart. The schedule stops the moment the value has settled.
    private var instrument: some View {
        TimelineView(.animation(minimumInterval: 1 / framesPerSecond, paused: dialIsResting)) { context in
            let value = drawnDisplay.value(at: context.date.timeIntervalSinceReferenceDate)
            let progress = progress(for: value)

            ZStack {
                arc(progress: progress)
                tip(progress: progress)
                readout(value: value)
            }
            .frame(width: diameter, height: diameter)
        }
    }

    private func progress(for metersPerSecond: Double) -> Double {
        let value = unit.speed(fromMetersPerSecond: max(0, metersPerSecond))
        return min(max(value / scale.maximum, 0), 1)
    }

    private func arc(progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: sweep / 360 * progress)
            .stroke(
                arcColor,
                style: StrokeStyle(lineWidth: ringWidth * 0.58, lineCap: .round)
            )
            .rotationEffect(.degrees(startAngle))
            .opacity(progress > 0.001 ? 1 : 0)
    }

    /// One dot rides the arc's tip. It rotates rather than being redrawn, so the
    /// movement is a transform and stays cheap while the arc trims.
    private func tip(progress: Double) -> some View {
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
        .opacity(progress > 0.001 ? 1 : 0)
        .rotationEffect(.degrees(startAngle + sweep * progress + 90))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func readout(value: Double) -> some View {
        VStack(spacing: 0) {
            Text(hasReading ? formatted(value) : "—")
                .font(
                    .system(
                        size: hasReading ? readoutFontSize : placeholderFontSize,
                        weight: .ultraLight,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .tracking(-1.2)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(hasReading ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
                .frame(height: readoutSlotHeight)

            Text(unit.title.uppercased())
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

    /// Formats the drawn value in the displayed unit. Tabular digits and a fixed
    /// slot keep the width stable while the number travels.
    private func formatted(_ metersPerSecond: Double) -> String {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "—" }
        return unit.speed(fromMetersPerSecond: metersPerSecond)
            .formatted(.number.precision(.fractionLength(0)))
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
