import FleetKit
import SwiftUI

struct BackendSection: View {
    let store: FleetDataStore
    let diagnostics: BackendDiagnosticsState
    let onProbeAccount: () -> Void
    let onReloadFleet: () async -> Void
    let onExportRawData: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        CardContainer(title: "\(store.provider.displayName) API", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 12) {
                DiagnosticGroupHeader("Connection")
                DiagnosticRow(label: "Auth", value: diagnostics.isSignedIn ? "Signed in" : "Not signed in")
                if let tokenExpiresAt = diagnostics.tokenExpiresAt {
                    DiagnosticRow(label: "Token expires", value: tokenExpiresAt.formatted(date: .abbreviated, time: .shortened))
                }

                if diagnostics.isSignedIn {
                    DiagnosticRow(label: "Token", value: diagnostics.tokenFormat)
                    if let tokenIssuer = diagnostics.tokenIssuer {
                        DiagnosticMonospacedValue(title: "Issuer", value: tokenIssuer)
                    }
                    if !diagnostics.tokenAudience.isEmpty {
                        DiagnosticMonospacedValue(title: "Audience", value: diagnostics.tokenAudience.joined(separator: ", "))
                    }
                    if !diagnostics.tokenScopes.isEmpty {
                        DiagnosticMonospacedValue(title: "Token scopes", value: diagnostics.tokenScopes.joined(separator: ", "))
                    }
                }

                DiagnosticMonospacedValue(title: "Device ID", value: diagnostics.deviceID)

                Divider()
                DiagnosticGroupHeader("Fleet data")
                DiagnosticRow(label: "Data", value: dataStatus)

                if let lastRefreshDate = store.lastRefreshDate {
                    DiagnosticRow(label: "Last refresh", value: lastRefreshDate.formatted(date: .abbreviated, time: .shortened))
                }

                DiagnosticRow(label: "Poll cursor", value: store.cursor.map(String.init) ?? "--")
                DiagnosticRow(label: "Vehicles", value: "\(store.vehicles.count)")
                DiagnosticRow(label: "Active drives", value: "\(store.activeDrivesByVIN.count)")
                DiagnosticRow(label: "Software states", value: "\(store.softwareUpdatesByVIN.count)")
                DiagnosticRow(label: "Recent drives", value: "\(store.recentDrives.count)")
                DiagnosticRow(label: "Locations", value: "\(store.selectedVehicleLocationHistory.count)")
                DiagnosticRow(label: "Telemetry points", value: "\(store.selectedVehicleTelemetrySeries.count)")
                DiagnosticRow(label: "Mapped drive routes", value: "\(store.driveRoutesBySessionID.count)")
                DiagnosticRow(label: "Raw export", value: store.rawDataExportMessage)

                if let rawDataExportURL = store.rawDataExportURL {
                    DiagnosticMonospacedValue(title: "Export file", value: rawDataExportURL.path)
                }

                if let capabilities = store.capabilities {
                    DiagnosticRow(label: "Capabilities", value: capabilitiesSummary(capabilities))
                }

                if let lastRequestID = store.lastRequestID {
                    DiagnosticMonospacedValue(title: "Request ID", value: lastRequestID)
                }

                if let lastErrorMessage = store.lastErrorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(lastErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                Divider()
                DiagnosticGroupHeader("Health check")

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Probe")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if diagnostics.isProbeRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(diagnostics.probeMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        probeAccountButton
                        reloadFleetButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        probeAccountButton
                        reloadFleetButton
                    }
                }

                Button {
                    onExportRawData()
                } label: {
                    HStack {
                        if store.isExportingRawData {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(store.isExportingRawData ? "Exporting Raw Data…" : "Export Raw Data")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!diagnostics.isSignedIn || store.selectedVehicle == nil || store.isExportingRawData)

                if diagnostics.isSignedIn {
                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
    }

    private var probeAccountButton: some View {
        Button {
            onProbeAccount()
        } label: {
            Label("Probe \(store.provider.displayName)", systemImage: "network")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(diagnostics.isProbeRunning)
    }

    private var reloadFleetButton: some View {
        Button {
            Task { await onReloadFleet() }
        } label: {
            Label("Reload Fleet", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(store.loadState.isLoading || store.isRefreshing)
    }

    private func capabilitiesSummary(_ capabilities: FleetCapabilities) -> String {
        "\(capabilities.scopes.count) access areas, \(capabilities.controlActions.count) controls"
    }

    private var dataStatus: String {
        if store.loadState.isLoading {
            return "Loading"
        }
        if store.isRefreshing {
            return "Refreshing"
        }
        if store.isLoadingActiveDrive {
            return "Loading active drive"
        }
        if store.isLoadingCharging {
            return "Loading charging"
        }
        if store.isLoadingDrives {
            return "Loading drives"
        }
        if store.isMutatingSoftware {
            return "Updating software"
        }
        if store.isLoadingSoftware {
            return "Loading software"
        }
        if store.isLoadingTelemetry {
            return "Loading telemetry"
        }
        if store.isExportingRawData {
            return "Exporting raw data"
        }
        if store.isShowingCachedData {
            return "Cached"
        }
        if store.vehicles.isEmpty {
            return "Empty"
        }
        return "Live"
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct BackendSectionPreviewer: View {
    let diagnostics: BackendDiagnosticsState
    let isSignedIn: Bool

    var body: some View {
        BackendSection(
            store: FleetDataStore.previewLoaded(),
            diagnostics: diagnostics,
            onProbeAccount: {},
            onReloadFleet: {},
            onExportRawData: {},
            onSignOut: {}
        )
    }
}

#Preview("Signed in") {
    let diagnostics = BackendDiagnosticsState(
        deviceID: "device-abc-123",
        isSignedIn: true,
        probeMessage: "Tessie API OK. Vehicles: 2.",
        tokenAudience: ["https://api.tessie.com"],
        tokenFormat: "Tessie access token",
        tokenIssuer: "Tessie Developer Settings",
        tokenScopes: ["vehicles", "vehicle_commands", "vehicle_history"]
    )
    return BackendSectionPreviewer(diagnostics: diagnostics, isSignedIn: true)
        .padding()
        .background(AppScreenBackground())
}

#Preview("Signed out") {
    let diagnostics = BackendDiagnosticsState(
        deviceID: "device-abc-123",
        isSignedIn: false,
        probeMessage: "Not run"
    )
    return BackendSectionPreviewer(diagnostics: diagnostics, isSignedIn: false)
        .padding()
        .background(AppScreenBackground())
}
