import AppIntents
import FleetKit
import SwiftUI

struct DashboardView: View {
    let store: FleetDataStore
    let isSignedIn: Bool
    let isAuthenticating: Bool
    var sandboxMode: FleetSandboxMode = .live
    let onSignIn: (String) -> Void
    let onReload: () async -> Void
    var onOpenSandboxSettings: () -> Void = {}
    var onEnableDemoCar: () -> Void = {}

    @State private var pendingCommand: VehicleControlCommand?
    @State private var pendingVehicleVIN: String?
    @State private var isShowingConfirmation = false

    private var canRefreshFleet: Bool {
        isSignedIn || sandboxMode == .demoVehicle
    }

    var body: some View {
        DashboardPostureContainer(
            store: store,
            isSignedIn: isSignedIn,
            isAuthenticating: isAuthenticating,
            sandboxMode: sandboxMode,
            onSignIn: onSignIn,
            onReload: onReload,
            onCommand: requestCommand,
            onOpenSandboxSettings: onOpenSandboxSettings,
            onEnableDemoCar: onEnableDemoCar
        )
        .observeDuoPosture()
        .background(AppScreenBackground())
        .navigationTitle(navigationTitle)
        .navigationSubtitle(store.selectedVehicle?.latest?.heroStatusLine ?? "")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarTitleMenu {
            if store.vehicles.count > 1 {
                vehicleSelectionMenuItems
            }
        }
        .toolbar {
            dashboardToolbarContent
        }
        .appEntityIdentifier(selectedVehicleEntityIdentifier)
        .onChange(of: store.selectedVehicle?.vin) {
            pendingCommand = nil
            pendingVehicleVIN = nil
            isShowingConfirmation = false
        }
        .vehicleCommandConfirmation(
            vehicleName: store.selectedVehicle?.name ?? "Vehicle",
            pendingCommand: $pendingCommand,
            isPresented: $isShowingConfirmation,
            onConfirm: performCommand
        )
    }

    private var navigationTitle: String {
        store.selectedVehicle?.name ?? "Vehicle"
    }

    @ToolbarContentBuilder
    private var dashboardToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                WidgetGalleryView()
            } label: {
                Label("Widgets & Controls", systemImage: "square.grid.2x2")
            }
        }

        if store.vehicles.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    vehicleSelectionMenuItems
                } label: {
                    Label("Switch Vehicle", systemImage: "car.2.fill")
                }
            }
        }

        if #available(iOS 27.3, macOS 27.3, visionOS 27.3, *) {
            ToolbarItem(placement: .topBarTrailing) {
                refreshToolbarButton
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                refreshToolbarButton
            }
        }
    }

    @ViewBuilder
    private var vehicleSelectionMenuItems: some View {
        ForEach(store.vehicles) { candidate in
            Button {
                selectVehicle(vin: candidate.vin)
            } label: {
                if candidate.vin == store.selectedVIN {
                    Label(candidate.name, systemImage: "checkmark")
                } else {
                    Text(candidate.name)
                }
            }
        }
    }

    private var refreshToolbarButton: some View {
        Button {
            Task { await onReload() }
        } label: {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh Vehicle", systemImage: "arrow.clockwise")
            }
        }
        .disabled(!canRefreshFleet || store.isRefreshing)
    }

    private func selectVehicle(vin: String) {
        guard vin != store.selectedVIN else { return }
        store.selectVehicle(vin: vin)
        Task { await FleetTokenBridge.sync(store: store) }
    }

    private func requestCommand(_ command: VehicleControlCommand) {
        guard let vehicle = store.selectedVehicle, vehicle.allows(command), !store.isRunningControl,
              !store.pendingControls.contains(where: { $0.conflicts(with: command) }) else { return }
        pendingVehicleVIN = store.selectedVehicle?.vin
        if command.requiresConfirmation {
            pendingCommand = command
            isShowingConfirmation = true
        } else {
            performCommand(command)
        }
    }

    private func performCommand(_ command: VehicleControlCommand) {
        pendingCommand = nil
        let confirmedVIN = pendingVehicleVIN
        pendingVehicleVIN = nil
        guard let targetVehicle = store.selectedVehicle, targetVehicle.vin == confirmedVIN else { return }
        Task {
            let succeeded = await store.runSelectedVehicleControl(command, for: targetVehicle.vin)
            if succeeded {
                FleetWidgetStore.reload()
                await FleetIntentDonations.donateControlCommand(command, for: targetVehicle)
            }
        }
    }

    private var selectedVehicleEntityIdentifier: EntityIdentifier? {
        guard let vin = store.selectedVehicle?.vin, !vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleEntity.self, identifier: vin)
    }
}

private struct DashboardPostureContainer: View {
    let store: FleetDataStore
    let isSignedIn: Bool
    let isAuthenticating: Bool
    let sandboxMode: FleetSandboxMode
    let onSignIn: (String) -> Void
    let onReload: () async -> Void
    let onCommand: (VehicleControlCommand) -> Void
    let onOpenSandboxSettings: () -> Void
    let onEnableDemoCar: () -> Void

    @Environment(\.duoPosture) private var duoPosture

    private var canRefreshFleet: Bool {
        isSignedIn || sandboxMode == .demoVehicle
    }

    var body: some View {
        if duoPosture.prefersSplitArrangement, let vehicle = store.selectedVehicle {
            DuoSplitWorkspace(primaryRatio: 0.52) {
                DashboardScroll(canRefresh: canRefreshFleet, onReload: onReload) {
                    DashboardShowroom(
                        store: store,
                        vehicle: vehicle,
                        compactHero: duoPosture.isPartiallyOpen && duoPosture.geometry.divisionAxis == .horizontal,
                        onCommand: onCommand
                    )

                    DashboardCardStack {
                        if let latitude = vehicle.latest?.latitude, let longitude = vehicle.latest?.longitude {
                            VehicleLocationCard(vehicleName: vehicle.name, latitude: latitude, longitude: longitude, mapHeight: 220)
                        }
                    }
                }
            } secondary: {
                DashboardScroll(canRefresh: canRefreshFleet, onReload: onReload) {
                    DashboardCardStack {
                        DashboardNotices(
                            store: store,
                            isSignedIn: isSignedIn,
                            isAuthenticating: isAuthenticating,
                            sandboxMode: sandboxMode,
                            onSignIn: onSignIn,
                            onOpenSandboxSettings: onOpenSandboxSettings
                        )

                        VehicleTelemetryCards(
                            vehicle: vehicle,
                            units: store.user?.units,
                            activeDrive: store.selectedVehicleActiveDrive,
                            chargingSessions: store.selectedVehicleChargingSessions,
                            includeLocation: false
                        )

                        DashboardSoftwareAndSiri(store: store, vehicle: vehicle)
                    }
                    .padding(.top, 12)
                }
            }
        } else if let vehicle = store.selectedVehicle {
            DashboardScroll(canRefresh: canRefreshFleet, onReload: onReload) {
                DashboardShowroom(
                    store: store,
                    vehicle: vehicle,
                    compactHero: duoPosture.prefersCompactHero,
                    onCommand: onCommand
                )

                DashboardCardStack {
                    DashboardNotices(
                        store: store,
                        isSignedIn: isSignedIn,
                        isAuthenticating: isAuthenticating,
                        sandboxMode: sandboxMode,
                        onSignIn: onSignIn,
                        onOpenSandboxSettings: onOpenSandboxSettings
                    )

                    VehicleTelemetryCards(
                        vehicle: vehicle,
                        units: store.user?.units,
                        activeDrive: store.selectedVehicleActiveDrive,
                        chargingSessions: store.selectedVehicleChargingSessions,
                        includeLocation: true
                    )

                    DashboardSoftwareAndSiri(store: store, vehicle: vehicle)
                }
            }
        } else {
            DashboardStandaloneStateScroll(
                store: store,
                isSignedIn: isSignedIn,
                isAuthenticating: isAuthenticating,
                sandboxMode: sandboxMode,
                onSignIn: onSignIn,
                onReload: onReload,
                onEnableDemoCar: onEnableDemoCar
            )
        }
    }
}

/// Vertical scroll container for a dashboard pane, capped to a readable width.
private struct DashboardScroll<Content: View>: View {
    let canRefresh: Bool
    let onReload: () async -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                content
            }
            .padding(.bottom, 28)
            .readableContentWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable {
            guard canRefresh else { return }
            await onReload()
        }
    }
}

private struct DashboardCardStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
    }
}

/// The car hero, its headline numbers, and the quick controls.
private struct DashboardShowroom: View {
    let store: FleetDataStore
    let vehicle: FleetVehicle
    let compactHero: Bool
    let onCommand: (VehicleControlCommand) -> Void

    var body: some View {
        VStack(spacing: compactHero ? 14 : 20) {
            VehicleHeroStage(
                vehicle: vehicle,
                units: store.user?.units,
                compact: compactHero,
                activeDrive: store.selectedVehicleActiveDrive,
                onCommand: onCommand,
                onLiveRefresh: { await store.refreshSelectedVehicleLive() }
            )

            if let snapshot = vehicle.latest {
                VehicleQuickActionBar(
                    snapshot: snapshot,
                    units: store.user?.units,
                    isRunningControl: store.isRunningControl,
                    activeControlAction: store.activeControlAction,
                    pendingControls: store.pendingControls,
                    controlMessage: store.vehicleControlMessage,
                    controlsEnabled: vehicle.allowsVehicleControls,
                    onCommand: onCommand
                )
                .padding(.horizontal, 16)
            }
        }
        .id(vehicle.vin)
    }
}

private struct DashboardNotices: View {
    let store: FleetDataStore
    let isSignedIn: Bool
    let isAuthenticating: Bool
    let sandboxMode: FleetSandboxMode
    let onSignIn: (String) -> Void
    let onOpenSandboxSettings: () -> Void

    var body: some View {
        if sandboxMode != .live {
            SandboxModeBanner(mode: sandboxMode, onOpenSettings: onOpenSandboxSettings)
        }

        if !isSignedIn, sandboxMode != .demoVehicle {
            SignInBanner(provider: store.provider, onSignIn: onSignIn, isAuthenticating: isAuthenticating)
        }

        if store.isShowingCachedData, sandboxMode != .demoVehicle {
            CachedDataNotice(cacheDate: store.cacheDate)
        }
    }
}

private struct SandboxModeBanner: View {
    let mode: FleetSandboxMode
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .dryRun ? "shield.lefthalf.filled" : "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(mode == .dryRun ? .orange : .blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .dryRun ? "Dry-Run Mode Active" : "Demo Car Mode Active")
                    .font(.subheadline.weight(.semibold))
                Text(mode == .dryRun ? "Commands are simulated and logged—your car is untouched." : "Testing with a simulated Model Y for Siri and app controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Sandbox") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .appSurface(cornerRadius: 18)
    }
}

private struct DashboardSoftwareAndSiri: View {
    let store: FleetDataStore
    let vehicle: FleetVehicle

    var body: some View {
        if let softwareUpdate = store.selectedVehicleSoftwareUpdate {
            SoftwareUpdateCard(
                store: store,
                update: softwareUpdate,
                vin: store.selectedVIN
            )
        } else if store.isLoadingSoftware {
            DashboardCard("Software", systemImage: "checkmark.seal") {
                LoadingRow(label: "Loading software…")
            }
        }

        AppIntentDiscoveryCard(vehicle: vehicle)
    }
}

private struct CachedDataNotice: View {
    let cacheDate: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Showing cached data")
                    .font(.subheadline.weight(.semibold))
                Group {
                    if let cacheDate {
                        RelativeTimeText(date: cacheDate, style: .updated)
                    } else {
                        Text("Refreshing live vehicle data…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .appSurface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardStandaloneStateScroll: View {
    let store: FleetDataStore
    let isSignedIn: Bool
    let isAuthenticating: Bool
    let sandboxMode: FleetSandboxMode
    let onSignIn: (String) -> Void
    let onReload: () async -> Void
    let onEnableDemoCar: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if !isSignedIn, sandboxMode != .demoVehicle {
                    SignInBanner(
                        provider: store.provider,
                        onSignIn: onSignIn,
                        isAuthenticating: isAuthenticating
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .duoSingleCardStage()

                    CardContainer(title: "Test without a car", systemImage: "sparkles") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Try Siri climate, security, and trip preparation with a simulated Model Y.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button("Try Demo Car Mode", systemImage: "car.fill") {
                                onEnableDemoCar()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 16)
                    .duoSingleCardStage()
                }

                if store.loadState.isLoading {
                    LoadingStateView(message: "Loading fleet data…")
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .duoSingleCardStage()
                } else if case .failed(let message) = store.loadState {
                    ErrorStateView(
                        message: message,
                        retry: { Task { await store.loadInitialData() } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .duoSingleCardStage()
                } else if isSignedIn || sandboxMode == .demoVehicle {
                    EmptyStateView(
                        title: "No vehicles",
                        systemImage: "car.side",
                        description: "No linked vehicles were returned."
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .duoSingleCardStage()
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            guard isSignedIn || sandboxMode == .demoVehicle else { return }
            await onReload()
        }
    }
}


struct LoadingStateView: View {
    let message: String

    var body: some View {
        CardContainer {
            LoadingRow(label: message)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        CardContainer(title: "Unable to load fleet", systemImage: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        CardContainer {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            .frame(maxWidth: .infinity)
        }
    }
}

struct LoadingCard: View {
    let title: String
    let message: String

    var body: some View {
        CardContainer(title: title) {
            LoadingRow(label: message)
        }
    }
}
