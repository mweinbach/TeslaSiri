#if DEBUG
import SwiftUI
import FleetKit

/// Signed-in dashboard previews for visual design iteration.
/// Render on different destinations (iPhone, iPhone Duo, iPad) and appearance
/// variants to audit the showroom-noir design language across form factors.
private struct SignedInDashboardPreview: View {
    let store = FleetDataStore.previewLoaded()

    var body: some View {
        NavigationStack {
            DashboardView(
                store: store,
                isSignedIn: true,
                isAuthenticating: false,
                onSignIn: { _ in },
                onReload: {}
            )
        }
        .tint(AppTheme.accent)
    }
}

#Preview("Dashboard · Signed In") {
    SignedInDashboardPreview()
}

#Preview("Dashboard · Signed In Dark") {
    SignedInDashboardPreview()
        .preferredColorScheme(.dark)
}
#endif
