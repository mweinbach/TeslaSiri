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
        .navigationSubtitle(navigationSubtitle)
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
            vehicleName: store.selectedVehicle?.name ?? String(localized: "Vehicle", comment: "Fallback vehicle name in command confirmation alert"),
            pendingCommand: $pendingCommand,
            isPresented: $isShowingConfirmation,
            onConfirm: performCommand
        )
    }

    private var navigationTitle: String {
        store.selectedVehicle?.name ?? String(localized: "Vehicle", comment: "Fallback navigation title when no vehicle is selected")
    }

    private var navigationSubtitle: String {
        if store.isWakingVehicle {
            return String(localized: "Waking vehicle…", comment: "Navigation subtitle while waking the car")
        }
        return store.selectedVehicle?.latest?.heroStatusLine(units: store.user?.units) ?? ""
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
        .accessibilityLabel(store.isWakingVehicle ? Text("Waking Vehicle") : Text("Refresh Vehicle"))
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
                            includeLocation: false,
                            isRunningControl: store.isRunningControl,
                            activeControlAction: store.activeControlAction,
                            pendingControls: store.pendingControls,
                            onCommand: onCommand
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
                        includeLocation: true,
                        isRunningControl: store.isRunningControl,
                        activeControlAction: store.activeControlAction,
                        pendingControls: store.pendingControls,
                        onCommand: onCommand
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
            VStack(spacing: 18) {
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
        VStack(spacing: compactHero ? 14 : 18) {
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
                    controlMessageIsError: store.vehicleControlMessageIsError,
                    isWaking: store.isWakingVehicle,
                    isRefreshing: store.isRefreshing,
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

    private var tint: Color {
        mode == .dryRun ? AppTheme.alertAmber : AppTheme.accent
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .dryRun ? "shield.lefthalf.filled" : "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Group {
                if mode == .dryRun {
                    Text("Dry-Run Mode · Commands simulated")
                } else {
                    Text("Demo Car · Simulated Model Y")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 6)

            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 3) {
                    Text("Sandbox")
                    Image(systemName: "chevron.forward")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appSurface(cornerRadius: 16)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.alertAmber)
                .accessibilityHidden(true)

            Text("Showing cached data")
                .font(.footnote.weight(.semibold))

            Spacer(minLength: 8)

            Group {
                if let cacheDate {
                    RelativeTimeText(date: cacheDate, style: .updated)
                } else {
                    Text("Refreshing…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appSurface(cornerRadius: 16)
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
            LazyVStack(spacing: 16) {
                if !isSignedIn, sandboxMode != .demoVehicle {
                    SignInBanner(
                        provider: store.provider,
                        onSignIn: onSignIn,
                        isAuthenticating: isAuthenticating
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .duoSingleCardStage()

                    CardContainer(title: "Explore without a car", systemImage: "sparkles") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Preview the 3D showroom, live controls, drives, and Siri workflows with a simulated Model Y.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                onEnableDemoCar()
                            } label: {
                                Label("Try Demo Car Mode", systemImage: "car.fill")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
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
    let message: LocalizedStringKey

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
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

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
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        CardContainer(title: title) {
            LoadingRow(label: message)
        }
    }
}
