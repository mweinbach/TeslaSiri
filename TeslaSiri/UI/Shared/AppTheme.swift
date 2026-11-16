import SwiftUI
import UIKit

/// Shared "showroom" palette used by every tab: a warm off-white page with white
/// surfaces in light mode, and a near-black page with lifted surfaces in dark mode.
/// The page colors match the backdrop of the `VehicleHero*` renders so the car blends
/// into the page edge to edge. Hairlines strengthen automatically when Increase Contrast is on.
enum AppTheme {
    static let pageBackground = dynamicColor(
        light: UIColor(red: 0.929, green: 0.918, blue: 0.910, alpha: 1),
        dark: UIColor(red: 0.010, green: 0.008, blue: 0.008, alpha: 1)
    )

    static let surface = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.082, green: 0.078, blue: 0.080, alpha: 1)
    )

    /// Fill for tiles nested inside a surface (metric tiles, rows).
    static let insetSurface = dynamicColor(
        light: UIColor(red: 0.949, green: 0.941, blue: 0.933, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.06)
    )

    static let hairline = Color(uiColor: UIColor { traits in
        let isHighContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: isHighContrast ? 0.34 : 0.10)
        }
        return UIColor(white: 0, alpha: isHighContrast ? 0.30 : 0.08)
    })

    static let surfaceShadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.05),
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
    static let tileCornerRadius: CGFloat = 20
    static let contentMaxWidth: CGFloat = 720

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    /// Rounded surface with a hairline border, used for cards and control tiles.
    func appSurface(
        cornerRadius: CGFloat = AppTheme.cardCornerRadius,
        fill: Color = AppTheme.surface
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(fill, in: shape)
            .overlay {
                shape.strokeBorder(AppTheme.hairline, lineWidth: 0.75)
            }
            .shadow(color: AppTheme.surfaceShadow, radius: 10, y: 3)
    }

    /// Centers content horizontally and caps its width so cards don't stretch edge-to-edge
    /// on iPad. Content stays pinned to the top: a lazy stack inside can grow after these
    /// frames were measured, and a vertically centered frame would then push its first
    /// rows up under the navigation bar.
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
