import SwiftUI
import UIKit

/// Velora's visual system.
///
/// One graphite identity in both appearances: an OLED-black instrument cluster
/// in Dark Mode and cool graphite paper in Light Mode. Light is designed on its
/// own terms - paper surfaces, cool shadows, graphite type - rather than an
/// inverted dark palette. Status hues never carry meaning alone; every use is
/// paired with a symbol or a label.
enum AppTheme {
    enum Colors {
        // Canvas
        static let canvas = dynamic(
            light: rgb(0.925, 0.929, 0.940),
            dark: rgb(0.043, 0.044, 0.049)
        )
        static let canvasDeep = dynamic(
            light: rgb(0.855, 0.860, 0.874),
            dark: rgb(0.008, 0.008, 0.010)
        )
        static let canvasSheen = dynamic(
            light: rgb(1, 1, 1, 0.92),
            dark: rgb(1, 1, 1, 0.070)
        )
        static let canvasVignette = dynamic(
            light: rgb(0.09, 0.10, 0.12, 0.085),
            dark: rgb(0, 0, 0, 0.66)
        )

        // Surfaces
        static let raised = dynamic(
            light: rgb(1, 1, 1, 0.90),
            dark: rgb(1, 1, 1, 0.052)
        )
        static let surface = dynamic(
            light: rgb(0, 0, 0, 0.038),
            dark: rgb(1, 1, 1, 0.040)
        )
        static let surfaceHighlight = dynamic(
            light: rgb(1, 1, 1, 0.80),
            dark: rgb(1, 1, 1, 0.055)
        )
        static let inset = dynamic(
            light: rgb(0, 0, 0, 0.055),
            dark: rgb(0, 0, 0, 0.30)
        )

        static let hairline = dynamic(
            light: rgb(0, 0, 0, 0.085),
            dark: rgb(1, 1, 1, 0.085)
        )
        static let hairlineStrong = dynamic(
            light: rgb(0, 0, 0, 0.20),
            dark: rgb(1, 1, 1, 0.16)
        )
        static let cardShadow = dynamic(
            light: rgb(0.08, 0.09, 0.11, 0.13),
            dark: rgb(0, 0, 0, 0)
        )

        // Type
        static let textPrimary = dynamic(
            light: rgb(0.075, 0.079, 0.088),
            dark: rgb(1, 1, 1, 0.96)
        )
        static let textSecondary = dynamic(
            light: rgb(0.32, 0.33, 0.36),
            dark: rgb(1, 1, 1, 0.64)
        )
        static let textTertiary = dynamic(
            light: rgb(0.44, 0.45, 0.48),
            dark: rgb(1, 1, 1, 0.46)
        )

        // Accent and status
        static let accent = dynamic(
            light: rgb(0.13, 0.13, 0.15),
            dark: rgb(0.93, 0.93, 0.95)
        )
        static let accentSoft = dynamic(
            light: rgb(0, 0, 0, 0.07),
            dark: rgb(1, 1, 1, 0.10)
        )
        static let success = dynamic(
            light: rgb(0.15, 0.45, 0.30),
            dark: rgb(0.62, 0.85, 0.70)
        )
        static let warning = dynamic(
            light: rgb(0.58, 0.40, 0.05),
            dark: rgb(0.95, 0.78, 0.48)
        )
        static let danger = dynamic(
            light: rgb(0.62, 0.16, 0.19),
            dark: rgb(0.94, 0.55, 0.55)
        )

        // Gauge
        static let gaugeDisc = dynamic(
            light: rgb(1, 1, 1, 0.62),
            dark: rgb(1, 1, 1, 0.030)
        )
        static let gaugeTrack = dynamic(
            light: rgb(0, 0, 0, 0.10),
            dark: rgb(1, 1, 1, 0.10)
        )
        static let gaugeProgress = dynamic(
            light: rgb(0.12, 0.12, 0.14),
            dark: rgb(1, 1, 1, 0.95)
        )
        static let gaugeTickMajor = dynamic(
            light: rgb(0, 0, 0, 0.34),
            dark: rgb(1, 1, 1, 0.40)
        )
        static let gaugeTickMinor = dynamic(
            light: rgb(0, 0, 0, 0.15),
            dark: rgb(1, 1, 1, 0.17)
        )
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let chip: CGFloat = 14
        static let control: CGFloat = 18
        static let card: CGFloat = 26
        static let hero: CGFloat = 34
    }

    enum Control {
        static let compact: CGFloat = 44
        static let primary: CGFloat = 54
        static let icon: CGFloat = 46
    }

    enum Typography {
        static let eyebrow = Font.caption2.weight(.bold)
        static let section = Font.caption.weight(.semibold)
        static let label = Font.caption2.weight(.semibold)
        static let body = Font.footnote
        static let metricValue = Font.system(.title, design: .rounded, weight: .semibold)
        static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        static let statusTitle = Font.footnote.weight(.semibold)
        static let statusDetail = Font.caption
        static let unit = Font.system(.footnote, design: .rounded, weight: .semibold)
        static let stateChip = Font.caption2.weight(.semibold)
    }

    enum Layout {
        static let maxContentWidth: CGFloat = 560
        static let minGaugeDiameter: CGFloat = 220
        static let maxGaugeDiameter: CGFloat = 360
    }
}

/// The three surface roles the interface is allowed to use. Cards hold content,
/// raised surfaces sit inside cards, inset surfaces read as wells. None of them
/// imitates Liquid Glass: glass stays on controls and chrome only.
enum VeloraSurfaceStyle {
    case card
    case raised
    case inset
}

private struct VeloraSurfaceModifier: ViewModifier {
    let style: VeloraSurfaceStyle
    let cornerRadius: CGFloat
    let padding: CGFloat

    private var fill: Color {
        switch style {
        case .card: AppTheme.Colors.raised
        case .raised: AppTheme.Colors.surface
        case .inset: AppTheme.Colors.inset
        }
    }

    private var shadowRadius: CGFloat {
        style == .card ? 20 : 0
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.Colors.surfaceHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .opacity(style == .inset ? 0.35 : 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AppTheme.Colors.hairline, lineWidth: 1)
                    }
                    .shadow(
                        color: AppTheme.Colors.cardShadow,
                        radius: shadowRadius,
                        x: 0,
                        y: shadowRadius > 0 ? 10 : 0
                    )
            }
    }
}

extension View {
    func veloraSurface(
        _ style: VeloraSurfaceStyle = .card,
        cornerRadius: CGFloat = AppTheme.Radius.card,
        padding: CGFloat = AppTheme.Spacing.md
    ) -> some View {
        modifier(VeloraSurfaceModifier(style: style, cornerRadius: cornerRadius, padding: padding))
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            AppTheme.Colors.canvas

            RadialGradient(
                colors: [
                    AppTheme.Colors.canvasSheen,
                    AppTheme.Colors.canvasSheen.opacity(0.32),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.20),
                startRadius: 0,
                endRadius: 540
            )

            RadialGradient(
                colors: [AppTheme.Colors.canvasSheen.opacity(0.45), .clear],
                center: UnitPoint(x: 0.5, y: 0.82),
                startRadius: 0,
                endRadius: 420
            )

            LinearGradient(
                colors: [
                    .clear,
                    AppTheme.Colors.canvasDeep.opacity(0.12),
                    AppTheme.Colors.canvasVignette
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func dynamic(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}
