import Foundation
import SwiftUI

struct GaugeScale {
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

struct SpeedGauge: View {
    let progress: Double
    let valueText: String
    let unitTitle: String
    let unitSpokenTitle: String
    let isLive: Bool
    let diameter: CGFloat
    let scale: GaugeScale
    /// Simulated fixes arrive many times per second. The numeric transition is
    /// skipped so the digits settle instead of animating continuously.
    var isSimulated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var unitScale: CGFloat = 1

    private let startAngle: Double = 135
    private let sweep: Double = 270

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var ringWidth: CGFloat {
        max(10, diameter * 0.034)
    }

    /// The dial is a fixed-size instrument: Dynamic Type grows the digits, but
    /// they stay inside the ring. A missing reading is drawn smaller so the
    /// placeholder dash does not read as a progress bar.
    private var isPlaceholder: Bool {
        valueText == "—"
    }

    private var speedFontSize: CGFloat {
        let base = isPlaceholder
            ? diameter * 0.10 * typeScale
            : diameter * 0.28 * typeScale
        let limit = diameter * (isPlaceholder ? 0.14 : 0.30)
        return min(base, limit)
    }

    private var unitFontSize: CGFloat {
        min(diameter * 0.052 * unitScale, diameter * 0.075)
    }

    /// Both rings are single, fully opaque strokes. The active arc used to be
    /// an AngularGradient whose opacity climbed from 0.35 to 1.0, so a short arc
    /// sat entirely in the grey start and a long arc faded from grey to white.
    /// A solid colour removes that speed-dependent brightness without an extra
    /// overlay. `Color.primary` is white in Dark Mode and graphite in Light
    /// Mode, where pure white would disappear against the paper background.
    private var trackColor: Color {
        Color.primary.opacity(0.12)
    }

    private var activeColor: Color {
        Color.primary
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                )
                .rotationEffect(.degrees(startAngle))

            Circle()
                .trim(from: 0, to: sweep / 360 * clampedProgress)
                .stroke(
                    activeColor,
                    style: StrokeStyle(lineWidth: ringWidth * 0.62, lineCap: .round)
                )
                .rotationEffect(.degrees(startAngle))
                .opacity(clampedProgress > 0.001 ? 1 : 0)
                .animation(
                    reduceMotion || isSimulated ? nil : .smooth(duration: 0.38),
                    value: clampedProgress
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.Colors.gaugeSheen, .clear],
                        center: UnitPoint(x: 0.5, y: 0.34),
                        startRadius: 0,
                        endRadius: diameter * 0.46
                    )
                )
                .padding(ringWidth * 1.4)
                .allowsHitTesting(false)

            ticks

            Circle()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                .padding(diameter * 0.115)

            VStack(spacing: 6) {
                Text(valueText)
                    .font(.system(size: speedFontSize, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .contentTransition(isSimulated ? .identity : .numericText())
                    .animation(
                        reduceMotion || isSimulated ? nil : .snappy(duration: 0.24),
                        value: valueText
                    )

                Text(unitTitle.uppercased())
                    .font(.system(size: unitFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .tracking(2.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, diameter * 0.18)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.speedLabel)
        .accessibilityValue(AccessibilityText.speedValue(valueText, spokenUnit: unitSpokenTitle))
    }

    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2

            let tickOuter = outerRadius - ringWidth - 3
            let majorLength = max(9, diameter * 0.032)
            let minorLength = max(4, diameter * 0.016)

            let minorCount = 28
            for index in 0...minorCount {
                let fraction = Double(index) / Double(minorCount)
                let angle = Angle.degrees(startAngle + fraction * sweep).radians
                let isMajor = scale.labels.contains { label in
                    abs(label / scale.maximum - fraction) < 0.001
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
                    with: .color(
                        isMajor
                            ? AppTheme.Colors.textSecondary.opacity(0.90)
                            : AppTheme.Colors.textTertiary.opacity(0.55)
                    ),
                    lineWidth: isMajor ? 1.6 : 1
                )
            }

            let labelRadius = outerRadius - ringWidth - majorLength - 14
            let fontSize = max(9, diameter * 0.034)
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
