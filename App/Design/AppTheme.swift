import SwiftUI
import UIKit

/// Velora's visual system.
///
/// Every colour resolves per interface style. The graphite identity is kept in
/// both appearances: deep graphite in Dark Mode, a cool "graphite paper" in
/// Light Mode. Nothing forces a colour scheme.
enum AppTheme {
    enum Colors {
        static let background = dynamic(
            light: rgb(0.912, 0.916, 0.928),
            dark: rgb(0.052, 0.053, 0.058)
        )
        static let backgroundDeep = dynamic(
            light: rgb(0.840, 0.845, 0.860),
            dark: rgb(0.012, 0.012, 0.015)
        )
        static let backgroundSheen = dynamic(
            light: rgb(1, 1, 1, 0.90),
            dark: rgb(1, 1, 1, 0.075)
        )
        static let backgroundVignette = dynamic(
            light: rgb(0.10, 0.11, 0.12, 0.07),
            dark: rgb(0, 0, 0, 0.62)
        )

        static let surface = dynamic(
            light: rgb(0, 0, 0, 0.035),
            dark: rgb(1, 1, 1, 0.045)
        )
        static let surfaceStrong = dynamic(
            light: rgb(0, 0, 0, 0.065),
            dark: rgb(1, 1, 1, 0.075)
        )
        static let stroke = dynamic(
            light: rgb(0, 0, 0, 0.09),
            dark: rgb(1, 1, 1, 0.08)
        )
        static let strokeStrong = dynamic(
            light: rgb(0, 0, 0, 0.22),
            dark: rgb(1, 1, 1, 0.16)
        )

        static let textPrimary = dynamic(
            light: rgb(0.09, 0.094, 0.102),
            dark: rgb(1, 1, 1, 0.96)
        )
        static let textSecondary = dynamic(
            light: rgb(0.34, 0.35, 0.38),
            dark: rgb(1, 1, 1, 0.66)
        )
        static let textTertiary = dynamic(
            light: rgb(0.44, 0.45, 0.48),
            dark: rgb(1, 1, 1, 0.50)
        )

        static let cardTint = dynamic(
            light: rgb(1, 1, 1, 0.55),
            dark: rgb(1, 1, 1, 0.02)
        )
        static let cardShadow = dynamic(
            light: rgb(0.10, 0.11, 0.13, 0.12),
            dark: rgb(0, 0, 0, 0)
        )
        static let gaugeSheen = dynamic(
            light: rgb(1, 1, 1, 0.85),
            dark: rgb(1, 1, 1, 0.05)
        )

        static let accent = dynamic(
            light: rgb(0.17, 0.17, 0.19),
            dark: rgb(0.87, 0.87, 0.89)
        )
        static let accentSoft = dynamic(
            light: rgb(0, 0, 0, 0.06),
            dark: rgb(1, 1, 1, 0.10)
        )
        static let success = dynamic(
            light: rgb(0.18, 0.47, 0.31),
            dark: rgb(0.68, 0.81, 0.70)
        )
        static let warning = dynamic(
            light: rgb(0.60, 0.42, 0.07),
            dark: rgb(0.91, 0.77, 0.53)
        )
        static let danger = dynamic(
            light: rgb(0.62, 0.18, 0.20),
            dark: rgb(0.89, 0.55, 0.55)
        )
        static let onAccent = dynamic(
            light: rgb(1, 1, 1),
            dark: rgb(0.07, 0.07, 0.08)
        )

        // Liquid Glass control tints: smoked graphite on paper in Light Mode,
        // lifted white frost in Dark Mode. Labels stay white on both.
        static let glassPrimaryTint = dynamic(
            light: rgb(0.10, 0.10, 0.11, 0.82),
            dark: rgb(1, 1, 1, 0.18)
        )
        static let glassSecondaryTint = dynamic(
            light: rgb(0.10, 0.10, 0.11, 0.58),
            dark: rgb(1, 1, 1, 0.06)
        )
        static let glassLabel = Color.white
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
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 28
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

struct AppBackground: View {
    var body: some View {
        ZStack {
            AppTheme.Colors.background

            RadialGradient(
                colors: [
                    AppTheme.Colors.backgroundSheen,
                    AppTheme.Colors.backgroundSheen.opacity(0.35),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 0,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .clear,
                    AppTheme.Colors.backgroundDeep.opacity(0.10),
                    AppTheme.Colors.backgroundVignette
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct AppCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppTheme.Colors.cardTint)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AppTheme.Colors.stroke, lineWidth: 1)
                    }
                    .shadow(
                        color: AppTheme.Colors.cardShadow,
                        radius: 18,
                        x: 0,
                        y: 10
                    )
            }
    }
}

extension View {
    func appCard(
        cornerRadius: CGFloat = AppTheme.Radius.large,
        padding: CGFloat = AppTheme.Spacing.md
    ) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
