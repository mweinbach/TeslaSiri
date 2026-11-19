import SwiftUI
import UIKit

/// Shared "showroom" palette used across every tab: ceramic alabaster with crisp white
/// cards in light mode, and deep obsidian with satin carbon surfaces in dark mode.
/// The page backdrop matches the `VehicleHero*` renders so the car floats edge-to-edge.
/// Signature Tesla crimson (`accent`) is reserved for active chrome and primary calls to action,
/// while semantic telemetry hues communicate charging, climate, and security states.
enum AppTheme {
    // MARK: - Brand & Semantic Telemetry Palette

    /// Signature Tesla-inspired crimson accent, calibrated for legibility in light and dark mode.
    static let accent = dynamicColor(
        light: UIColor(red: 0.824, green: 0.110, blue: 0.196, alpha: 1),
        dark: UIColor(red: 0.949, green: 0.212, blue: 0.298, alpha: 1)
    )

    /// Active charging and healthy battery energy indicator.
    static let chargeGreen = dynamicColor(
        light: UIColor(red: 0.118, green: 0.659, blue: 0.341, alpha: 1),
        dark: UIColor(red: 0.188, green: 0.820, blue: 0.447, alpha: 1)
    )

    /// Active cabin cooling / HVAC airflow indicator.
    static let climateBlue = dynamicColor(
        light: UIColor(red: 0.039, green: 0.478, blue: 0.859, alpha: 1),
        dark: UIColor(red: 0.247, green: 0.667, blue: 1.000, alpha: 1)
    )

    /// Active heating / defrost / unlocked attention indicator.
    static let alertAmber = dynamicColor(
        light: UIColor(red: 0.878, green: 0.467, blue: 0.020, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.624, blue: 0.125, alpha: 1)
    )

    // MARK: - Showroom Surfaces

    static let pageBackground = dynamicColor(
        light: UIColor(red: 0.929, green: 0.918, blue: 0.910, alpha: 1),
        dark: UIColor(red: 0.010, green: 0.008, blue: 0.008, alpha: 1)
    )

    static let surface = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.086, green: 0.084, blue: 0.090, alpha: 1)
    )

    /// Fill for tiles nested inside a surface (metric tiles, input fields, rows).
    static let insetSurface = dynamicColor(
        light: UIColor(red: 0.953, green: 0.947, blue: 0.941, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.065)
    )

    static let hairline = Color(uiColor: UIColor { traits in
        let isHighContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: isHighContrast ? 0.36 : 0.105)
        }
        return UIColor(white: 0, alpha: isHighContrast ? 0.28 : 0.075)
    })

    /// Subtle top-lit highlight for dark mode cards (machined anodized edge feel).
    static let topEdgeHighlight = Color(uiColor: UIColor { traits in
        let isHighContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: isHighContrast ? 0.42 : 0.17)
        }
        return UIColor(white: 0, alpha: isHighContrast ? 0.28 : 0.07)
    })

    static let surfaceShadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.045),
        dark: .clear
    )

    /// Track behind segmented selectors.
    static let segmentTrack = dynamicColor(
        light: UIColor(white: 0, alpha: 0.05),
        dark: UIColor(white: 1, alpha: 0.07)
    )

    /// Selected segment / raised element that must stand out from `surface` in dark mode.
    static let raisedSurface = dynamicColor(
        light: .white,
        dark: UIColor(white: 1, alpha: 0.16)
    )

    static let cardCornerRadius: CGFloat = 24
    static let tileCornerRadius: CGFloat = 18
    static let contentMaxWidth: CGFloat = 720

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    /// Rounded showroom surface with a subtle top-lit hairline border and light-mode elevation.
    func appSurface(
        cornerRadius: CGFloat = AppTheme.cardCornerRadius,
        fill: Color = AppTheme.surface
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.topEdgeHighlight, AppTheme.hairline],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
            .shadow(color: AppTheme.surfaceShadow, radius: 12, y: 4)
    }

    /// Centers content horizontally and caps its width so cards don't stretch edge-to-edge
    /// on iPad. Content stays pinned to the top so lazy stacks never shift under the nav bar.
    func readableContentWidth() -> some View {
        frame(maxWidth: AppTheme.contentMaxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Relative timestamp ("Updated 4 minutes ago") that refreshes itself while on screen.
struct RelativeTimeText: View {
    enum Style {
        case plain
        case updated
        case started
    }

    let date: Date
    var style: Style = .plain

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            switch style {
            case .plain:
                Text(date, format: Self.format)
            case .updated:
                Text("Updated \(date, format: Self.format)")
            case .started:
                Text("Started \(date, format: Self.format)")
            }
        }
    }

    private static let format = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
}

