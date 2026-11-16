import FleetKit
import SwiftUI

struct SignInBanner: View {
    var provider: FleetProvider = .tessie
    let onSignIn: (String) -> Void
    let isAuthenticating: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var accessToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            bannerHeader

            SecureField("\(provider.displayName) access token", text: $accessToken)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .submitLabel(.go)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.hairline)
                }
                .onSubmit(connect)

            Button(action: connect) {
                HStack(spacing: 8) {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "key.fill")
                    }

                    Text(isAuthenticating ? "Connecting…" : "Connect \(provider.displayName)")
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isAuthenticating || trimmedToken.isEmpty)

            tokenHelp
        }
        .padding(20)
        .appSurface(cornerRadius: 28)
    }

    @ViewBuilder
    private var bannerHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                bannerIcon
                bannerCopy
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                bannerIcon
                bannerCopy
            }
        }
    }

    private var bannerIcon: some View {
        Image(systemName: "car.side.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    private var bannerCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connect with \(provider.displayName)")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(provider == .tessie
                 ? "Paste a Tessie access token to see your vehicle and drive history."
                 : "Create a personal access token with the tesla-accounts and vehicles scopes. For vehicle controls, add the controls scope and use a Teslascope premium subscription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tokenHelp: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                generateTokenLink
                keychainNote
            }
        } else {
            HStack {
                generateTokenLink
                Spacer()
                keychainNote
            }
        }
    }

    private var generateTokenLink: some View {
        Link(destination: provider.tokenSettingsURL) {
            Label("Generate a token", systemImage: "arrow.up.right.square")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
    }

    private var keychainNote: some View {
        Label("Stored in Keychain", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trimmedToken: String {
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        guard !trimmedToken.isEmpty, !isAuthenticating else { return }
        onSignIn(trimmedToken)
    }
}

#Preview("Idle") {
    ScrollView {
        SignInBanner(onSignIn: { _ in }, isAuthenticating: false)
            .padding()
    }
    .background {
        AppScreenBackground()
    }
}

#Preview("Authenticating") {
    ScrollView {
        SignInBanner(onSignIn: { _ in }, isAuthenticating: true)
            .padding()
    }
    .background {
        AppScreenBackground()
    }
}
