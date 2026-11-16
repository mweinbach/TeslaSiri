import FleetKit
import SwiftUI

struct ProviderSettingsView: View {
    let provider: FleetProvider
    let isSignedIn: Bool
    let isAuthenticating: Bool
    let onSelectProvider: (FleetProvider) -> Void
    let onSignIn: (String) -> Void
    let onSignOut: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CardContainer(title: "Vehicle data", systemImage: "car.side") {
                    LabeledContent("Provider") {
                        Picker("Provider", selection: Binding(get: { provider }, set: onSelectProvider)) {
                            ForEach(FleetProvider.allCases, id: \.self) { choice in
                                Text(choice.displayName).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(isAuthenticating)
                    }
                }

                if isSignedIn {
                    CardContainer(title: provider.displayName, systemImage: "person.crop.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Connected", systemImage: "checkmark.circle")
                            Button("Disconnect \(provider.displayName)", role: .destructive, action: onSignOut)
                                .buttonStyle(.bordered)
                                .disabled(isAuthenticating)
                        }
                    }
                } else {
                    SignInBanner(provider: provider, onSignIn: onSignIn, isAuthenticating: isAuthenticating)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(AppScreenBackground())
        .navigationTitle("Settings")
    }
}

#Preview("Teslascope setup") {
    NavigationStack {
        ProviderSettingsView(
            provider: .teslascope,
            isSignedIn: false,
            isAuthenticating: false,
            onSelectProvider: { _ in },
            onSignIn: { _ in },
            onSignOut: {}
        )
    }
}
