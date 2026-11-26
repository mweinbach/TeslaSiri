import FleetKit
import SwiftUI

struct ProviderSettingsView: View {
    let provider: FleetProvider
    let isSignedIn: Bool
    let isAuthenticating: Bool
    var sandboxMode: FleetSandboxMode = .live
    var vehicleCount: Int = 0
    var selectedVehicleName: String? = nil
    var lastUpdated: Date? = nil
    let onSelectProvider: (FleetProvider) -> Void
    let onSignIn: (String) -> Void
    let onSignOut: () -> Void
    var onOpenSandboxSettings: () -> Void = {}

    var body: some View {
        Form {
            if sandboxMode != .live {
                Section("Sandbox") {
                    LabeledContent("Mode") {
                        StatusBadge(
                            sandboxMode == .dryRun
                                ? LocalizedStringKey("Dry-Run")
                                : LocalizedStringKey("Demo Car"),
                            systemImage: sandboxMode == .dryRun ? "shield.lefthalf.filled" : "sparkles",
                            tint: sandboxMode == .dryRun ? AppTheme.alertAmber : AppTheme.accent
                        )
                    }

                    Button {
                        onOpenSandboxSettings()
                    } label: {
                        LabeledContent("Manage Sandbox & Scenarios") {
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Picker("Data Provider", selection: Binding(get: { provider }, set: onSelectProvider)) {
                    ForEach(FleetProvider.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .disabled(isAuthenticating)
            } header: {
                Text("Vehicle Data")
            } footer: {
                Text("Used by Wattie, Siri tools, App Shortcuts, and widgets.")
            }

            if isSignedIn {
                Section(provider.displayName) {
                    LabeledContent("Status") {
                        StatusBadge("Connected", systemImage: "checkmark.circle.fill", tint: AppTheme.chargeGreen)
                    }

                    if let selectedVehicleName {
                        LabeledContent("Active Vehicle", value: selectedVehicleName)
                    }

                    if vehicleCount > 0 {
                        LabeledContent("Linked Vehicles", value: vehicleCount.formatted())
                            .monospacedDigit()
                    }

                    if let lastUpdated {
                        LabeledContent("Last Telemetry") {
                            RelativeTimeText(date: lastUpdated)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Disconnect \(provider.displayName)", role: .destructive, action: onSignOut)
                        .disabled(isAuthenticating)
                }
            } else {
                Section {
                    SignInBanner(provider: provider, onSignIn: onSignIn, isAuthenticating: isAuthenticating)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section("Extensions") {
                NavigationLink {
                    WidgetGalleryView()
                } label: {
                    Label("Widgets & Controls", systemImage: "square.grid.2x2")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppScreenBackground())
        .navigationTitle("Settings")
    }
}
