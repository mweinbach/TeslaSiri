import AppIntents
import FleetKit
import Foundation
import SwiftUI

enum AppTab: Hashable, Identifiable, CaseIterable {
    case dashboard
    case drives
    case diagnostics
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Vehicle"
        case .drives: "Drives"
        case .diagnostics: "Diagnostics"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "car.fill"
        case .drives: "map"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape"
        }
    }
}

struct BackendDiagnosticsState: Equatable {
    var deviceID = "--"
    var isProbeRunning = false
    var isSignedIn = false
    var probeMessage = "Not run"
    var tokenAudience: [String] = []
    var tokenExpiresAt: Date?
    var tokenFormat = "--"
    var tokenIssuer: String?
    var tokenScopes: [String] = []

    mutating func clearTokenInspection() {
        tokenAudience = []
        tokenFormat = "--"
        tokenIssuer = nil
        tokenScopes = []
    }
}

struct AppRootView: View {
    let store: FleetDataStore
    let tokenStore: FleetProviderTokenStore
    @Binding var selectedTab: AppTab
    let isCurrentSession: () -> Bool
    let onSelectProvider: (FleetProvider) -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var authErrorMessage: String?
    @State private var diagnostics = BackendDiagnosticsState()
    @State private var requestedDriveSessionID: String?
    @State private var spotlightSearchTerm = ""
    @State private var isAuthenticating = false
    @State private var sandboxMode = FleetSandboxStore.shared.mode()
    @State private var sandboxPreset: FleetDemoPreset = .mildCommute
    @State private var sandboxDemoState: FleetDemoVehicleState?
    @State private var sandboxCommandLog: [FleetSimulatedCommandEntry] = []
    @State private var siriVerificationRunner = DemoSiriVerificationRunner.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        tabContent(for: tab)
                    }
                }
            }
        }
        .onAppIntentExecution(OpenVehicleIntent.self) { intent in
            openVehicle(intent.target.id, tab: .dashboard)
        }
        .onChange(of: sandboxMode) { _, _ in
            FleetWidgetStore.reload()
        }
        .onOpenURL { url in
            guard url.scheme == "wattie", url.host == "vehicle",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let vin = components.queryItems?.first(where: { $0.name == "vin" })?.value else { return }
            Task {
                await store.loadInitialDataIfNeeded()
                guard isCurrentSession(), store.vehicles.contains(where: { $0.vin == vin }) else { return }
                openVehicle(vin, tab: .dashboard)
            }
        }
        .onAppIntentExecution(OpenVehicleStatusIntent.self) { intent in
            openVehicle(intent.target.vin, tab: .dashboard)
        }
        .onAppIntentExecution(OpenSoftwareUpdateIntent.self) { intent in
            openVehicle(intent.target.vin, tab: .dashboard)
        }
        .onAppIntentExecution(OpenReleaseNoteIntent.self) { intent in
            openVehicle(intent.target.vin, tab: .dashboard)
        }
        .onAppIntentExecution(OpenDriveIntent.self) { intent in
            requestedDriveSessionID = intent.target.id
            openVehicle(intent.target.vin, tab: .drives)
        }
        .onAppIntentExecution(SearchFleetIntent.self) { intent in
            spotlightSearchTerm = intent.criteria.term
            selectedTab = .diagnostics
        }
        .onContinueUserActivity(CarSiriVoicePhrase.warmUp.rawValue) { activity in
            handleCarVoiceShortcut(.warmUp, activity: activity)
        }
        .onContinueUserActivity(CarSiriVoicePhrase.coolDown.rawValue) { activity in
            handleCarVoiceShortcut(.coolDown, activity: activity)
        }
        .onContinueUserActivity(CarSiriVoicePhrase.lock.rawValue) { activity in
            handleCarVoiceShortcut(.lock, activity: activity)
        }
        .onContinueUserActivity(CarSiriVoicePhrase.checkStatus.rawValue) { activity in
            handleCarVoiceShortcut(.checkStatus, activity: activity)
        }
        .alert("Connection Failed", isPresented: authErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authErrorMessage ?? "Unknown error")
        }
        .task {
            refreshSandboxSnapshot()
            refreshDiagnostics()
            await FleetTokenBridge.sync(store: store)
            guard isCurrentSession(), !Task.isCancelled else { return }
            if diagnostics.isSignedIn || sandboxMode == .demoVehicle {
                await store.loadInitialDataIfNeeded()
                guard isCurrentSession(), !Task.isCancelled else { return }
                FleetTokenBridge.syncSelectedVehicle(store: store)
            }
            configureFleetPolling(for: scenePhase)
        }
        .onChange(of: siriVerificationRunner.isRunning) { _, running in
            if !running {
                refreshSandboxSnapshot()
                if sandboxMode == .demoVehicle {
                    Task { await store.loadInitialData() }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            configureFleetPolling(for: newPhase)
            if newPhase == .active {
                Task { await FleetTokenBridge.sync(store: store) }
                refreshSandboxSnapshot()
                if sandboxMode == .demoVehicle {
                    Task { await store.refresh() }
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            refreshSandboxSnapshot()
        }
        .onChange(of: store.isRunningControl) { _, isRunning in
            if !isRunning {
                refreshSandboxSnapshot()
            }
        }
        .onChange(of: store.isMutatingSoftware) { _, isMutating in
            if !isMutating {
                refreshSandboxSnapshot()
            }
        }
        .onChange(of: store.selectedVIN) { previousVIN, _ in
            guard isCurrentSession(), !isAuthenticating,
                  !store.vehicles.contains(where: { $0.vin == previousVIN }),
                  sandboxMode == .demoVehicle || (try? tokenStore.loadAccessToken()) != nil else {
                return
            }
            FleetTokenBridge.syncSelectedVehicle(store: store)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView(
                store: store,
                isSignedIn: diagnostics.isSignedIn,
                isAuthenticating: isAuthenticating,
                sandboxMode: sandboxMode,
                onSignIn: { token in
                    Task { await signIn(accessToken: token) }
                },
                onReload: {
                    await reloadFleet()
                },
                onOpenSandboxSettings: {
                    selectedTab = .diagnostics
                },
                onEnableDemoCar: {
                    Task { await updateSandboxMode(.demoVehicle) }
                }
            )
        case .settings:
            ProviderSettingsView(
                provider: store.provider,
                isSignedIn: diagnostics.isSignedIn,
                isAuthenticating: isAuthenticating,
                onSelectProvider: onSelectProvider,
                onSignIn: { token in Task { await signIn(accessToken: token) } },
                onSignOut: { Task { await signOut() } }
            )
        case .drives:
            DrivesView(
                store: store,
                requestedSessionID: requestedDriveSessionID,
                onReload: {
                    await reloadFleet()
                }
            )
        case .diagnostics:
            if let sandboxDemoState {
                DiagnosticsView(
                    store: store,
                    diagnostics: diagnostics,
                    spotlightSearchTerm: spotlightSearchTerm,
                    sandboxMode: sandboxMode,
                    sandboxPreset: sandboxPreset,
                    sandboxDemoState: sandboxDemoState,
                    sandboxCommandLog: sandboxCommandLog,
                    siriVerificationRunner: siriVerificationRunner,
                    onProbeAccount: {
                        Task { await runBackendProbe() }
                    },
                    onReloadFleet: {
                        await reloadFleet()
                        await store.refreshSelectedVehicleTelemetry()
                    },
                    onExportRawData: {
                        Task { await exportRawData() }
                    },
                    onSignOut: {
                        Task { await signOut() }
                    },
                    onSelectSandboxMode: { newMode in
                        Task { await updateSandboxMode(newMode) }
                    },
                    onSelectSandboxPreset: { newPreset in
                        Task { await applySandboxPreset(newPreset) }
                    },
                    onResetSandboxPreset: {
                        Task { await applySandboxPreset(sandboxPreset) }
                    },
                    onRefreshSandboxLog: {
                        refreshSandboxSnapshot()
                        if sandboxMode == .demoVehicle {
                            Task { await store.refresh() }
                        }
                    },
                    onClearSandboxLog: {
                        FleetSandboxStore.shared.clearCommandLog()
                        refreshSandboxSnapshot()
                    },
                    onRunSiriVerification: {
                        Task { await runDemoSiriVerification() }
                    }
                )
            } else {
                ProgressView()
            }
        }
    }

    private var authErrorBinding: Binding<Bool> {
        Binding {
            authErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                authErrorMessage = nil
            }
        }
    }

    // MARK: - Actions

    private func signIn(accessToken: String) async {
        guard isCurrentSession(), !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let validationClient = FleetBackend.makeAPIClient(
                provider: store.provider,
                accessTokenProvider: StaticFleetAccessTokenProvider(token: accessToken)
            )
            let bootstrap = try await validationClient.bootstrap()
            guard isCurrentSession() else { return }
            let outgoingVehicles = store.vehicles
            let previousRevision = FleetSharedTokenStore.shared.sessionRevision
            try tokenStore.saveAccessToken(accessToken)
            await store.reset(clearCache: true)
            guard isCurrentSession() else { return }
            if FleetSharedTokenStore.shared.sessionRevision != previousRevision {
                await FleetTokenBridge.clearVehicleSystemData(for: outgoingVehicles)
                guard isCurrentSession() else { return }
            }
            diagnostics.probeMessage = "Connected to \(store.provider.displayName). Loading \(bootstrap.data.vehicles.count) vehicle(s)."
            refreshDiagnostics()
            await store.loadInitialData(validatedBootstrap: bootstrap)
            guard isCurrentSession() else { return }
            await FleetTokenBridge.sync(store: store)
            refreshDiagnostics()
            configureFleetPolling(for: scenePhase)
        } catch {
            authErrorMessage = error.localizedDescription
            diagnostics.probeMessage = error.localizedDescription
            refreshDiagnostics()
        }
    }

    private func reloadFleet() async {
        await store.refresh()
        guard isCurrentSession() else { return }
        await FleetTokenBridge.sync(store: store)
        guard isCurrentSession() else { return }
        await FleetIntentDonations.donateManualStatusRefresh(for: store.selectedVehicle)
        refreshSandboxSnapshot()
        refreshDiagnostics()
    }

    private func updateSandboxMode(_ newMode: FleetSandboxMode) async {
        guard isCurrentSession() else { return }
        let previousMode = FleetSandboxStore.shared.mode()
        guard previousMode != newMode else { return }

        FleetSandboxStore.shared.setMode(newMode)
        refreshSandboxSnapshot()

        let crossedDemoBoundary = (previousMode == .demoVehicle) != (newMode == .demoVehicle)
        if crossedDemoBoundary {
            try? await FleetSpotlightIndexer.deleteAllIndexedEntities()
            guard isCurrentSession() else { return }
            await store.reset(clearCache: false)
            guard isCurrentSession() else { return }
            if newMode == .demoVehicle || diagnostics.isSignedIn {
                await store.loadInitialDataIfNeeded()
                await FleetTokenBridge.sync(store: store)
            } else {
                FleetTokenBridge.clear(provider: store.provider)
            }
            configureFleetPolling(for: scenePhase)
        }
        refreshSandboxSnapshot()
        refreshDiagnostics()
    }

    private func applySandboxPreset(_ preset: FleetDemoPreset) async {
        guard isCurrentSession() else { return }
        FleetSandboxStore.shared.applyPreset(preset)
        refreshSandboxSnapshot()
        if sandboxMode == .demoVehicle {
            await store.loadInitialData()
            await FleetTokenBridge.sync(store: store)
            refreshSandboxSnapshot()
        }
    }

    private func runDemoSiriVerification() async {
        if FleetSandboxStore.shared.mode() != .demoVehicle {
            await updateSandboxMode(.demoVehicle)
        }
        guard isCurrentSession() else { return }
        await siriVerificationRunner.runAllOnDemoCar()
        guard isCurrentSession() else { return }
        refreshSandboxSnapshot()
        await store.loadInitialData()
        await FleetTokenBridge.sync(store: store)
        refreshSandboxSnapshot()
        refreshDiagnostics()
    }

    private func refreshSandboxSnapshot() {
        sandboxMode = FleetSandboxStore.shared.mode()
        guard selectedTab == .diagnostics else { return }
        sandboxPreset = FleetSandboxStore.shared.selectedPreset()
        sandboxDemoState = FleetSandboxStore.shared.demoState()
        sandboxCommandLog = FleetSandboxStore.shared.commandLog()
    }

    private func openVehicle(_ vin: String, tab: AppTab) {
        guard isCurrentSession() else { return }
        if !vin.isEmpty, vin != store.selectedVIN {
            store.selectVehicle(vin: vin)
            Task { await FleetTokenBridge.sync(store: store) }
        }
        selectedTab = tab
    }

    private func handleCarVoiceShortcut(_ phrase: CarSiriVoicePhrase, activity: NSUserActivity) {
        let vin = activity.userInfo?["vin"] as? String
        if let vin, !vin.isEmpty, vin != store.selectedVIN {
            store.selectVehicle(vin: vin)
        }
        selectedTab = .dashboard
        Task {
            do {
                guard isCurrentSession() else { return }
                let initialSession = FleetIntentService.make().sessionScopeID
                let result = try await phrase.perform(vinOverride: vin)
                guard let initialSession, initialSession == FleetIntentService.make().sessionScopeID else { return }
                if let vin = result.vin, store.selectedVehicle?.vin == vin {
                    switch phrase {
                    case .warmUp, .coolDown: store.reconcileAcknowledgedControl(.climate(shouldTurnOn: true), for: vin, expected: true)
                    case .lock: store.reconcileAcknowledgedControl(.lock(shouldLock: true), for: vin, expected: true)
                    case .checkStatus: store.showVehicleStatusSummary(result.summary, for: vin)
                    }
                }
                refreshSandboxSnapshot()
            } catch {
                authErrorMessage = error.localizedDescription
            }
        }
    }

    private func configureFleetPolling(for phase: ScenePhase) {
        if isCurrentSession(), phase == .active, diagnostics.isSignedIn || sandboxMode == .demoVehicle {
            store.startPolling()
        } else {
            store.stopPolling()
        }
    }

    private func runBackendProbe() async {
        diagnostics.isProbeRunning = true
        diagnostics.probeMessage = "Checking \(store.provider.displayName) API access."
        defer {
            diagnostics.isProbeRunning = false
            refreshDiagnostics()
        }

        do {
            let apiClient = FleetBackend.makeAPIClient(provider: store.provider)
            let bootstrap = try await apiClient.bootstrap()
            diagnostics.probeMessage = backendProbeMessage(
                vehicleCount: bootstrap.data.vehicles.count,
                requestID: bootstrap.requestID
            )
        } catch {
            diagnostics.probeMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        guard isCurrentSession(), !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let outgoingVehicles = store.vehicles
            try tokenStore.deleteAccessToken()
            FleetTokenBridge.clear(provider: store.provider)
            await store.reset(clearCache: true)
            guard isCurrentSession() else { return }
            await FleetTokenBridge.clearVehicleSystemData(for: outgoingVehicles)
            guard isCurrentSession() else { return }
            if sandboxMode == .demoVehicle {
                await store.loadInitialData()
                guard isCurrentSession() else { return }
                await FleetTokenBridge.sync(store: store)
            }
            diagnostics.probeMessage = "Disconnected \(store.provider.displayName) and cleared cached fleet data."
            refreshSandboxSnapshot()
            refreshDiagnostics()
        } catch {
            authErrorMessage = error.localizedDescription
            diagnostics.probeMessage = error.localizedDescription
            refreshDiagnostics()
        }
    }

    private func exportRawData() async {
        await store.exportSelectedVehicleRawData()
        refreshDiagnostics()
    }

    // MARK: - Diagnostics

    private func refreshDiagnostics() {
        do {
            let token = try tokenStore.loadAccessToken()
            diagnostics.isSignedIn = token != nil
            diagnostics.tokenExpiresAt = nil

            diagnostics.clearTokenInspection()
            if token != nil, store.provider == .tessie {
                diagnostics.tokenAudience = ["https://api.tessie.com"]
                diagnostics.tokenFormat = "Tessie access token"
                diagnostics.tokenIssuer = "Tessie Developer Settings"
                diagnostics.tokenScopes = TessieModelAdapter.capabilities.scopes
            } else if token != nil {
                diagnostics.tokenFormat = "Personal access token"
                diagnostics.tokenIssuer = store.provider.displayName
            }
        } catch {
            diagnostics.isSignedIn = false
            diagnostics.tokenExpiresAt = nil
            diagnostics.clearTokenInspection()
            diagnostics.probeMessage = error.localizedDescription
        }

        do {
            diagnostics.deviceID = try FleetBackend.makeDeviceIdentity().deviceID()
        } catch {
            diagnostics.deviceID = "--"
            diagnostics.probeMessage = error.localizedDescription
        }
    }

    private func backendProbeMessage(vehicleCount: Int, requestID: String?) -> String {
        var message = "\(store.provider.displayName) API OK. Vehicles: \(vehicleCount)."
        if let requestID {
            message += " Request ID: \(requestID)."
        }
        return message
    }
}

#Preview {
    AppRootView(
        store: .previewLoaded(),
        tokenStore: FleetProviderTokenStore(provider: .tessie),
        selectedTab: .constant(.dashboard),
        isCurrentSession: { true },
        onSelectProvider: { _ in }
    )
}
