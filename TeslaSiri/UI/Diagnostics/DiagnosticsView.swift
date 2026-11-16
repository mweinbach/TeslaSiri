import FleetKit
import SwiftUI

struct DiagnosticsView: View {
    let store: FleetDataStore
    let diagnostics: BackendDiagnosticsState
    let spotlightSearchTerm: String
    var sandboxMode: FleetSandboxMode = .live
    var sandboxPreset: FleetDemoPreset = .mildCommute
    var sandboxDemoState: FleetDemoVehicleState = .make(preset: .mildCommute)
    var sandboxCommandLog: [FleetSimulatedCommandEntry] = []
    var siriVerificationRunner: DemoSiriVerificationRunner?
    let onProbeAccount: () -> Void
    let onReloadFleet: () async -> Void
    let onExportRawData: () -> Void
    let onSignOut: () -> Void
    var onSelectSandboxMode: (FleetSandboxMode) -> Void = { _ in }
    var onSelectSandboxPreset: (FleetDemoPreset) -> Void = { _ in }
    var onResetSandboxPreset: () -> Void = {}
    var onRefreshSandboxLog: () -> Void = {}
    var onClearSandboxLog: () -> Void = {}
    var onRunSiriVerification: () -> Void = {}

    var body: some View {
        DiagnosticsPostureContainer(
            store: store,
            diagnostics: diagnostics,
            spotlightSearchTerm: spotlightSearchTerm,
            sandboxMode: sandboxMode,
            sandboxPreset: sandboxPreset,
            sandboxDemoState: sandboxDemoState,
            sandboxCommandLog: sandboxCommandLog,
            siriVerificationRunner: siriVerificationRunner,
            onProbeAccount: onProbeAccount,
            onReloadFleet: onReloadFleet,
            onExportRawData: onExportRawData,
            onSignOut: onSignOut,
            onSelectSandboxMode: onSelectSandboxMode,
            onSelectSandboxPreset: onSelectSandboxPreset,
            onResetSandboxPreset: onResetSandboxPreset,
            onRefreshSandboxLog: onRefreshSandboxLog,
            onClearSandboxLog: onClearSandboxLog,
            onRunSiriVerification: onRunSiriVerification
        )
        .observeDuoPosture()
        .background(AppScreenBackground())
        .task(id: store.selectedVehicle?.vin) {
            await store.refreshSelectedVehicleTelemetry()
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            diagnosticsToolbarContent
        }
    }

    @ToolbarContentBuilder
    private var diagnosticsToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onProbeAccount()
            } label: {
                if diagnostics.isProbeRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Probe Tessie", systemImage: "network")
                }
            }
            .disabled(diagnostics.isProbeRunning)
        }

        if #available(iOS 27.3, macOS 27.3, visionOS 27.3, *) {
            ToolbarItem(placement: .topBarTrailing) {
                reloadToolbarButton
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                reloadToolbarButton
            }
        }
    }

    private var reloadToolbarButton: some View {
        Button {
            Task { await onReloadFleet() }
        } label: {
            if store.loadState.isLoading || store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Reload Fleet", systemImage: "arrow.clockwise")
            }
        }
        .disabled(store.loadState.isLoading || store.isRefreshing)
    }
}

private struct DiagnosticsPostureContainer: View {
    let store: FleetDataStore
    let diagnostics: BackendDiagnosticsState
    let spotlightSearchTerm: String
    let sandboxMode: FleetSandboxMode
    let sandboxPreset: FleetDemoPreset
    let sandboxDemoState: FleetDemoVehicleState
    let sandboxCommandLog: [FleetSimulatedCommandEntry]
    let siriVerificationRunner: DemoSiriVerificationRunner?
    let onProbeAccount: () -> Void
    let onReloadFleet: () async -> Void
    let onExportRawData: () -> Void
    let onSignOut: () -> Void
    let onSelectSandboxMode: (FleetSandboxMode) -> Void
    let onSelectSandboxPreset: (FleetDemoPreset) -> Void
    let onResetSandboxPreset: () -> Void
    let onRefreshSandboxLog: () -> Void
    let onClearSandboxLog: () -> Void
    let onRunSiriVerification: () -> Void

    @Environment(\.duoPosture) private var duoPosture

    private var hasRequestedSpotlightSearch: Bool {
        !spotlightSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var spotlightSearchSection: some View {
        SpotlightDebugSection(
            isSignedIn: diagnostics.isSignedIn || sandboxMode == .demoVehicle,
            requestedQuery: spotlightSearchTerm
        )
    }

    private var sandboxSection: some View {
        SandboxDebugSection(
            mode: sandboxMode,
            preset: sandboxPreset,
            demoState: sandboxDemoState,
            commandLog: sandboxCommandLog,
            verificationRunner: siriVerificationRunner,
            onSelectMode: onSelectSandboxMode,
            onSelectPreset: onSelectSandboxPreset,
            onResetPreset: onResetSandboxPreset,
            onRefreshLog: onRefreshSandboxLog,
            onClearLog: onClearSandboxLog,
            onRunSiriVerification: onRunSiriVerification
        )
    }

    var body: some View {
        if duoPosture.prefersSplitArrangement {
            DuoSplitWorkspace(primaryRatio: 0.50) {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        sandboxSection

                        NormalizedDataSection(store: store)

                        if let user = store.user {
                            AccountSection(
                                email: user.email,
                                units: user.units,
                                scopes: user.scopes
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: AppTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await onReloadFleet()
                }
            } secondary: {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if hasRequestedSpotlightSearch {
                            spotlightSearchSection
                        }

                        BackendSection(
                            store: store,
                            diagnostics: diagnostics,
                            onProbeAccount: onProbeAccount,
                            onReloadFleet: onReloadFleet,
                            onExportRawData: onExportRawData,
                            onSignOut: onSignOut
                        )

                        if !hasRequestedSpotlightSearch {
                            spotlightSearchSection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: AppTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await onReloadFleet()
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if hasRequestedSpotlightSearch {
                        spotlightSearchSection
                    }

                    sandboxSection

                    BackendSection(
                        store: store,
                        diagnostics: diagnostics,
                        onProbeAccount: onProbeAccount,
                        onReloadFleet: onReloadFleet,
                        onExportRawData: onExportRawData,
                        onSignOut: onSignOut
                    )

                    NormalizedDataSection(store: store)

                    if !hasRequestedSpotlightSearch {
                        spotlightSearchSection
                    }

                    if let user = store.user {
                        AccountSection(
                            email: user.email,
                            units: user.units,
                            scopes: user.scopes
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .readableContentWidth()
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await onReloadFleet()
            }
        }
    }
}

@MainActor
private struct DiagnosticsPreviewer: View {
    var spotlightSearchTerm = ""

    var body: some View {
        let diagnostics = BackendDiagnosticsState(
            deviceID: "device-abc-123",
            isSignedIn: true,
            probeMessage: "Tessie API OK. Vehicles: 2.",
            tokenAudience: ["https://api.tessie.com"],
            tokenFormat: "Tessie access token",
            tokenIssuer: "Tessie Developer Settings",
            tokenScopes: ["vehicles", "vehicle_commands", "vehicle_history"]
        )

        return NavigationStack {
            DiagnosticsView(
                store: FleetDataStore.previewLoaded(),
                diagnostics: diagnostics,
                spotlightSearchTerm: spotlightSearchTerm,
                onProbeAccount: {},
                onReloadFleet: {},
                onExportRawData: {},
                onSignOut: {}
            )
        }
    }
}

#Preview("Diagnostics — Light") {
    DiagnosticsPreviewer()
}

#Preview("Diagnostics — Dark") {
    DiagnosticsPreviewer()
        .preferredColorScheme(.dark)
}
