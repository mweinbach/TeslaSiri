import AppIntents
import FleetKit
import Foundation
import SwiftUI

enum AppTab: Hashable, Identifiable, CaseIterable {
    case dashboard
    case drives
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Vehicle"
        case .drives: "Drives"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "car.fill"
        case .drives: "map"
        case .diagnostics: "stethoscope"
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
    let tokenStore: TessieAccessTokenStore

    @Environment(\.scenePhase) private var scenePhase

    @State private var authErrorMessage: String?
    @State private var diagnostics = BackendDiagnosticsState()
    @State private var requestedDriveSessionID: String?
    @State private var selectedTab: AppTab = CommandLine.arguments.contains("--verify-demo-siri") ? .diagnostics : .dashboard
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
                guard store.vehicles.contains(where: { $0.vin == vin }) else { return }
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
            if diagnostics.isSignedIn || sandboxMode == .demoVehicle {
                await store.loadInitialDataIfNeeded()
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
            guard !isAuthenticating,
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
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let validationClient = FleetAPIClient(accessTokenProvider: StaticFleetAccessTokenProvider(token: accessToken))
            let bootstrap = try await validationClient.bootstrap()
            let previousScope = FleetIntentService.make().sessionScopeID
            try tokenStore.saveAccessToken(accessToken)
            if FleetIntentService.make().sessionScopeID != previousScope {
                try? await FleetSpotlightIndexer.deleteAllIndexedEntities()
            }
            await store.reset(clearCache: true)
            diagnostics.probeMessage = "Connected to Tessie. Loading \(bootstrap.data.vehicles.count) vehicle(s)."
            refreshDiagnostics()
            await store.loadInitialData(validatedBootstrap: bootstrap)
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
        await FleetTokenBridge.sync(store: store)
        await FleetIntentDonations.donateManualStatusRefresh(for: store.selectedVehicle)
        refreshSandboxSnapshot()
        refreshDiagnostics()
    }

    private func updateSandboxMode(_ newMode: FleetSandboxMode) async {
        let previousMode = FleetSandboxStore.shared.mode()
        guard previousMode != newMode else { return }

        FleetSandboxStore.shared.setMode(newMode)
        refreshSandboxSnapshot()

        let crossedDemoBoundary = (previousMode == .demoVehicle) != (newMode == .demoVehicle)
        if crossedDemoBoundary {
            try? await FleetSpotlightIndexer.deleteAllIndexedEntities()
            await store.reset(clearCache: false)
            if newMode == .demoVehicle || diagnostics.isSignedIn {
                await store.loadInitialDataIfNeeded()
                await FleetTokenBridge.sync(store: store)
            } else {
                FleetTokenBridge.clear()
            }
            configureFleetPolling(for: scenePhase)
        }
        refreshSandboxSnapshot()
        refreshDiagnostics()
    }

    private func applySandboxPreset(_ preset: FleetDemoPreset) async {
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
        await siriVerificationRunner.runAllOnDemoCar()
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
        if phase == .active, diagnostics.isSignedIn || sandboxMode == .demoVehicle {
            store.startPolling()
        } else {
            store.stopPolling()
        }
    }

    private func runBackendProbe() async {
        diagnostics.isProbeRunning = true
        diagnostics.probeMessage = "Checking Tessie API access."
        defer {
            diagnostics.isProbeRunning = false
            refreshDiagnostics()
        }

        do {
            let apiClient = FleetBackend.makeAPIClient()
            let vehiclePage = try await apiClient.vehicles(includeLive: true)
            diagnostics.probeMessage = backendProbeMessage(
                vehicleCount: vehiclePage.data.count,
                requestID: vehiclePage.requestID
            )
        } catch {
            diagnostics.probeMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        do {
            try tokenStore.deleteAccessToken()
            FleetTokenBridge.clear()
            await store.reset(clearCache: true)
            if sandboxMode == .demoVehicle {
                await store.loadInitialData()
                FleetTokenBridge.syncSelectedVehicle(store: store, forceShortcutRefresh: true)
            } else {
                try? await FleetSpotlightIndexer.deleteAllIndexedEntities()
                store.stopPolling()
            }
            diagnostics.probeMessage = "Disconnected Tessie and cleared cached fleet data."
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

            if token != nil {
                diagnostics.tokenAudience = ["https://api.tessie.com"]
                diagnostics.tokenFormat = "Tessie access token"
                diagnostics.tokenIssuer = "Tessie Developer Settings"
                diagnostics.tokenScopes = TessieModelAdapter.capabilities.scopes
            } else {
                diagnostics.clearTokenInspection()
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
        var message = "Tessie API OK. Vehicles: \(vehicleCount)."
        if let requestID {
            message += " Request ID: \(requestID)."
        }
        return message
    }
}

#Preview {
    AppRootView(
        store: .previewLoaded(),
        tokenStore: TessieAccessTokenStore()
    )
}
