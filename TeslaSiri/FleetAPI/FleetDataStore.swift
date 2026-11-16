import FleetKit
import Foundation
import Observation

@MainActor
@Observable
final class FleetDataStore {
    // MARK: - Types

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)

        var isLoading: Bool {
            if case .loading = self {
                return true
            }
            return false
        }
    }

    private enum LoadingKind: Hashable {
        case activeDrive
        case charging
        case drives
        case software
        case telemetry
    }

    // MARK: - Dependencies & Background Tasks

    let provider: FleetProvider
    @ObservationIgnored private let apiClient: any FleetDataLoading
    @ObservationIgnored private let cache: any FleetDataCaching
    @TaskLocal private static var batchesCacheWrites = false
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var isHydratingCache = false
    @ObservationIgnored private var lastRosterRefresh: Date?
    @ObservationIgnored private var spotlightRosterScope: String?
    @ObservationIgnored private var loadingCounts: [LoadingKind: Int] = [:]
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var selectionRefreshTask: Task<Void, Never>?

    // MARK: - Fleet Data State

    private(set) var user: FleetUser?
    private(set) var capabilities: FleetCapabilities?
    private(set) var vehicles: [FleetVehicle] = []
    var selectedVIN: String? {
        didSet {
            if selectedVIN != oldValue { vehicleControlMessage = nil }
        }
    }

    private(set) var activeCharging: [FleetChargeSession] = []
    private(set) var activeDrivesByVIN: [String: FleetActiveDriveSession] = [:]
    private(set) var recentDrives: [FleetDriveSession] = []
    private(set) var driveRoutesBySessionID: [String: [FleetRoutePoint]] = [:]
    private(set) var softwareUpdatesByVIN: [String: FleetSoftwareUpdate] = [:]
    private(set) var locationHistoryByVIN: [String: [FleetRoutePoint]] = [:]
    private(set) var telemetrySeriesByVIN: [String: [FleetTelemetrySeriesPoint]] = [:]

    // MARK: - Sync & Cache Metadata

    private(set) var loadState: LoadState = .idle
    private(set) var cursor: Int64?
    private(set) var cacheDate: Date?
    private(set) var isShowingCachedData = false
    private(set) var lastRefreshDate: Date?
    private(set) var lastRequestID: String?
    private(set) var lastErrorMessage: String?

    // MARK: - Loading & Action State

    private(set) var isRefreshing = false
    private(set) var isLoadingActiveDrive = false
    private(set) var isLoadingCharging = false
    private(set) var isLoadingDrives = false
    private(set) var isLoadingSoftware = false
    private(set) var isLoadingTelemetry = false

    private(set) var isRunningControl = false
    private(set) var activeControlAction: String?
    private struct PendingControl {
        let expectedState: Bool
        let startedAt: ContinuousClock.Instant
    }
    private var pendingControlsByVIN: [String: [VehicleControlCommand: PendingControl]] = [:]
    @ObservationIgnored private var lastCommandStartedAt: ContinuousClock.Instant?

    var pendingControls: Set<VehicleControlCommand> {
        guard let vin = selectedVehicle?.vin, let commands = pendingControlsByVIN[vin] else { return [] }
        return Set(commands.keys)
    }
    private(set) var vehicleControlMessage: String?

    private(set) var isMutatingSoftware = false
    private(set) var softwareActionMessage = "Not run"

    private(set) var isExportingRawData = false
    private(set) var rawDataExportMessage = "Not run"
    private(set) var rawDataExportURL: URL?

    // MARK: - Selected Vehicle Computed State

    var latestSnapshotsByVIN: [String: FleetLatestSnapshot] {
        Dictionary(uniqueKeysWithValues: vehicles.compactMap { vehicle in
            guard let latest = vehicle.latest else {
                return nil
            }
            return (vehicle.vin, latest)
        })
    }

    var selectedVehicle: FleetVehicle? {
        guard let selectedVIN else {
            return vehicles.first
        }
        return vehicles.first { $0.vin == selectedVIN } ?? vehicles.first
    }

    var selectedVehicleRecentDrives: [FleetDriveSession] {
        guard let selectedVIN = selectedVehicle?.vin else {
            return recentDrives
        }
        return recentDrives.filter { $0.vin == selectedVIN }
    }

    var selectedVehicleChargingSessions: [FleetChargeSession] {
        guard let vin = selectedVehicle?.vin else {
            return []
        }
        return activeCharging.filter { $0.vin == vin }
    }

    var selectedVehicleActiveDrive: FleetActiveDriveSession? {
        guard let selectedVIN = selectedVehicle?.vin else {
            return nil
        }
        return activeDrivesByVIN[selectedVIN]
    }

    var selectedVehicleLocationHistory: [FleetRoutePoint] {
        guard let selectedVIN = selectedVehicle?.vin else {
            return []
        }
        return locationHistoryByVIN[selectedVIN] ?? []
    }

    var selectedVehicleTelemetrySeries: [FleetTelemetrySeriesPoint] {
        guard let selectedVIN = selectedVehicle?.vin else {
            return []
        }
        return telemetrySeriesByVIN[selectedVIN] ?? []
    }

    var selectedVehicleSoftwareUpdate: FleetSoftwareUpdate? {
        guard let selectedVehicle else {
            return nil
        }
        return softwareUpdatesByVIN[selectedVehicle.vin] ?? selectedVehicle.latest?.software
    }

    var cachedDriveRouteCount: Int {
        driveRoutesBySessionID.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Initialization & Polling

    init(apiClient: any FleetDataLoading, cache: any FleetDataCaching = FleetNoDataCache(), provider: FleetProvider = .tessie) {
        self.provider = provider
        self.apiClient = apiClient
        self.cache = cache
    }

    func startPolling(interval: TimeInterval = 60) {
        guard pollingTask == nil else {
            return
        }

        let pollingInterval = max(interval, 15)
        pollingTask = Task { [weak self] in
            await self?.pollFleetData(every: pollingInterval)
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Bootstrap, Sync & Selection

    func loadInitialDataIfNeeded() async {
        guard vehicles.isEmpty, !loadState.isLoading, !isHydratingCache else { return }
        let generation = sessionGeneration
        isHydratingCache = true
        defer {
            if generation == sessionGeneration { isHydratingCache = false }
        }
        await hydrateFromCacheIfAvailable(generation: generation)
        guard generation == sessionGeneration, !Task.isCancelled else { return }

        if vehicles.isEmpty {
            await loadInitialData()
        } else {
            await refresh()
        }
    }

    func loadInitialData(validatedBootstrap: FleetAPIPage<FleetBootstrap>? = nil) async {
        guard !loadState.isLoading else { return }
        let generation = sessionGeneration
        let rosterScope = FleetIntentService.make().sessionScopeID
        loadState = .loading
        lastErrorMessage = nil

        do {
            let page: FleetAPIPage<FleetBootstrap>
            if let validatedBootstrap, FleetSandboxStore.shared.mode() != .demoVehicle {
                page = validatedBootstrap
            } else {
                page = try await apiClient.bootstrap()
            }
            try Task.checkCancellation()
            guard generation == sessionGeneration else { return }
            spotlightRosterScope = rosterScope
            applyBootstrap(page.data, cursor: page.cursor, requestID: page.requestID, isCached: false)
            await refreshCapabilitiesIfNeeded(generation: generation)
            if generation == sessionGeneration, !Task.isCancelled {
                await refreshSelectedVehicleDetails(onlyMissing: true)
            }
            if generation == sessionGeneration { loadState = .loaded }
        } catch {
            guard generation == sessionGeneration else { return }
            if Task.isCancelled || error is CancellationError {
                loadState = vehicles.isEmpty ? .idle : .loaded
                return
            }
            let message = error.localizedDescription
            lastErrorMessage = message
            loadState = vehicles.isEmpty ? .failed(message) : .loaded
        }
    }

    func refresh() async {
        guard let cursor else {
            await loadInitialData()
            return
        }

        guard !isRefreshing else { return }
        let generation = sessionGeneration
        let rosterScope = FleetIntentService.make().sessionScopeID
        isRefreshing = true
        lastErrorMessage = nil
        defer {
            if generation == sessionGeneration { isRefreshing = false }
        }

        do {
            let page = try await apiClient.changes(since: cursor)
            guard !Task.isCancelled, generation == sessionGeneration, self.cursor == cursor else { return }

            if let roster = page.data.vehicles {
                spotlightRosterScope = rosterScope
                applyVehicleRoster(roster)
            } else {
                mergeLatestSnapshots(page.data.latest)
            }
            self.cursor = page.cursor ?? cursor
            isShowingCachedData = false
            lastRequestID = page.requestID
            lastRefreshDate = Date()
            lastRosterRefresh = lastRefreshDate
            loadState = .loaded
            await refreshSelectedVehicleDetails()
        } catch {
            guard !Task.isCancelled, generation == sessionGeneration, self.cursor == cursor else { return }
            let message = error.localizedDescription
            lastErrorMessage = message
            if vehicles.isEmpty {
                loadState = .failed(message)
            }
        }
    }

    func selectVehicle(vin: String) {
        guard selectedVIN != vin, vehicles.contains(where: { $0.vin == vin }) else { return }
        selectedVIN = vin
        selectionRefreshTask?.cancel()
        selectionRefreshTask = Task {
            guard !Task.isCancelled else { return }
            await refreshSelectedVehicleDetails()
        }
    }

    func reset(clearCache: Bool) async {
        sessionGeneration += 1
        isHydratingCache = false
        stopPolling()
        selectionRefreshTask?.cancel()
        selectionRefreshTask = nil
        loadingCounts = [:]

        user = nil
        capabilities = nil
        vehicles = []
        selectedVIN = nil

        activeCharging = []
        activeDrivesByVIN = [:]
        recentDrives = []
        driveRoutesBySessionID = [:]
        softwareUpdatesByVIN = [:]
        locationHistoryByVIN = [:]
        telemetrySeriesByVIN = [:]

        loadState = .idle
        cursor = nil
        cacheDate = nil
        isShowingCachedData = false
        lastRefreshDate = nil
        lastRosterRefresh = nil
        spotlightRosterScope = nil
        lastRequestID = nil
        lastErrorMessage = nil

        isRefreshing = false
        isLoadingActiveDrive = false
        isLoadingCharging = false
        isLoadingDrives = false
        isLoadingSoftware = false
        isLoadingTelemetry = false

        isRunningControl = false
        activeControlAction = nil
        pendingControlsByVIN.removeAll()
        lastCommandStartedAt = nil
        vehicleControlMessage = nil

        isMutatingSoftware = false
        softwareActionMessage = "Not run"

        isExportingRawData = false
        rawDataExportMessage = "Not run"
        rawDataExportURL = nil

        if clearCache {
            try? await cache.clear()
        }
    }

    func route(for drive: FleetDriveSession) -> [FleetRoutePoint] {
        driveRoutesBySessionID[drive.sessionID] ?? []
    }

    // MARK: - Vehicle Refresh & Control Actions

    func refreshSelectedVehicleLive(includingTires: Bool = true) async {
        await performSelectedVehicleRefresh { vin, generation in
            let page = try await apiClient.latestSnapshot(vin: vin, includingTires: includingTires)
            try validateReadResult(for: vin, generation: generation)
            var snapshot = page.data
            if FleetDataNormalizer.normalizedString(snapshot.vin) == nil {
                snapshot.vin = vin
            }
            if !includingTires, let previous = selectedVehicle?.latest?.tires { snapshot.tires = previous }
            mergeLatestSnapshots([snapshot])
            return page.requestID
        }
    }

    @discardableResult
    func runSelectedVehicleControl(_ command: VehicleControlCommand, for vin: String) async -> Bool {
        guard let vehicle = selectedVehicle, vehicle.vin == vin, vehicle.allows(command), !isRunningControl,
              !pendingControls.contains(where: { $0.conflicts(with: command) }) else {
            return false
        }

        let generation = sessionGeneration
        let expected = command.expectedState
        lastCommandStartedAt = .now
        let climateService: FleetIntentService? = if case .climate = command { .make() } else { nil }
        let climateScope = climateService?.sessionScopeID
        activeControlAction = command.action
        isRunningControl = true
        vehicleControlMessage = "Sending command…"
        defer {
            if generation == sessionGeneration {
                activeControlAction = nil
                isRunningControl = false
            }
        }

        do {
            let page = try await apiClient.runControl(action: command.action, vin: vin, params: command.parameters)
            guard generation == sessionGeneration else { return false }
            let mode = FleetSandboxStore.shared.mode()
            if let climateService, let climateScope, climateService.sessionScopeID == climateScope {
                climateService.recordClimateControl(command.action, vin: vin)
            }
            guard selectedVehicle?.vin == vin else { return true }
            lastErrorMessage = nil
            lastRequestID = page.requestID ?? lastRequestID
            switch mode {
            case .live:
                vehicleControlMessage = "Command sent"
            case .dryRun:
                vehicleControlMessage = "Simulated (Dry-Run) — car untouched"
            case .demoVehicle:
                vehicleControlMessage = "Simulated on demo car"
            }
            if command != .honk, command != .flashLights {
                reconcileAcknowledgedControl(command, for: vin, expected: expected)
            }
            return true
        } catch {
            guard generation == sessionGeneration, selectedVehicle?.vin == vin else { return false }
            let message = error.localizedDescription
            lastErrorMessage = message
            vehicleControlMessage = message
            return false
        }
    }

    func showVehicleStatusSummary(_ summary: String, for vin: String) {
        guard selectedVehicle?.vin == vin, !isRunningControl else { return }
        vehicleControlMessage = summary
    }

    func reconcileAcknowledgedControl(_ command: VehicleControlCommand, for vin: String, expected: Bool?) {
        guard selectedVehicle?.vin == vin, FleetSandboxStore.shared.mode() != .dryRun else { return }
        let generation = sessionGeneration
        let acknowledgedAt = ContinuousClock.now
        lastCommandStartedAt = acknowledgedAt
        if let expected, command.observedState(in: selectedVehicle?.latest) != expected {
            pendingControlsByVIN[vin, default: [:]][command] = PendingControl(expectedState: expected, startedAt: acknowledgedAt)
        }

        Task {
            guard generation == sessionGeneration, selectedVehicle?.vin == vin else { return }
            await refreshSelectedVehicleLive(includingTires: false)
        }
        guard pendingControlsByVIN[vin]?[command]?.startedAt == acknowledgedAt else { return }
        Task {
            // A sleeping vehicle can keep returning the previous state. Allow a deliberate retry.
            try? await Task.sleep(until: acknowledgedAt + .seconds(15), clock: .continuous)
            guard generation == sessionGeneration, pendingControlsByVIN[vin]?[command]?.startedAt == acknowledgedAt else { return }
            pendingControlsByVIN[vin]?[command] = nil
            if selectedVehicle?.vin == vin, lastCommandStartedAt == acknowledgedAt, vehicleControlMessage == "Command sent" {
                vehicleControlMessage = "Command sent. Updated vehicle state is unavailable."
            }
        }
    }

    private func reconcilePendingControls(with snapshot: FleetLatestSnapshot) {
        guard let pending = pendingControlsByVIN[snapshot.vin] else { return }
        pendingControlsByVIN[snapshot.vin] = pending.filter { command, pending in
            command.observedState(in: snapshot) != pending.expectedState
        }
    }

    func refreshSelectedVehicleActiveDrive(includeRoute: Bool = false, routeMaxPoints: Int = 200) async {
        await performSelectedVehicleRefresh(loading: .activeDrive) { vin, generation in
            let page = try await apiClient.activeDrive(
                vin: vin,
                includeRoute: includeRoute,
                routeMaxPoints: includeRoute ? routeMaxPoints : nil
            )
            try validateReadResult(for: vin, generation: generation)
            mergeActiveDrive(page.data, for: vin)
            return page.requestID
        }
    }

    func refreshSelectedVehicleChargingSessions(limit: Int = 10) async {
        await performSelectedVehicleRefresh(loading: .charging) { vin, generation in
            let page = try await apiClient.chargingSessions(vin: vin, limit: limit)
            try validateReadResult(for: vin, generation: generation)
            mergeChargingSessions(page.data, for: vin)
            return page.requestID
        }
    }

    @discardableResult
    func refreshSelectedVehicleSoftware(includeReleaseNotes: Bool = true, forceRefresh: Bool = false) async -> Bool {
        await performSelectedVehicleRefresh(loading: .software) { vin, generation in
            let page = try await apiClient.softwareUpdate(
                vin: vin,
                includeReleaseNotes: includeReleaseNotes,
                refresh: forceRefresh
            )
            try validateReadResult(for: vin, generation: generation)
            if let softwareUpdate = FleetDataNormalizer.softwareUpdate(page.data) {
                mergeSoftwareUpdates([vin: softwareUpdate])
            } else {
                softwareUpdatesByVIN.removeValue(forKey: vin)
            }
            return page.requestID
        }
    }

    @discardableResult
    func installSelectedVehicleSoftwareUpdate(offsetSec: Int = 0) async -> Bool {
        await performSoftwareMutation(
            progressMessage: "Scheduling software update.",
            successMessage: offsetSec == 0 ? "Requested software install." : "Scheduled software install."
        ) { vin in
            try await apiClient.installSoftwareUpdate(vin: vin, offsetSec: offsetSec)
        }
    }

    @discardableResult
    func cancelSelectedVehicleSoftwareUpdate() async -> Bool {
        await performSoftwareMutation(
            progressMessage: "Canceling software update.",
            successMessage: "Canceled software update."
        ) { vin in
            try await apiClient.cancelSoftwareUpdate(vin: vin)
        }
    }

    /// A longer drive history for the selected vehicle, without touching the cached recent
    /// drives. A failed read leaves the previous place index usable.
    func selectedVehicleDriveHistory(limit: Int = 200) async -> [FleetDriveSession]? {
        guard let vin = selectedVehicle?.vin else { return nil }
        let generation = sessionGeneration
        do {
            let page = try await apiClient.drives(vin: vin, limit: limit, includeRoute: false)
            try validateReadResult(for: vin, generation: generation)
            return page.data
        } catch {
            return nil
        }
    }

    func refreshSelectedVehicleDrives(limit: Int = 10) async {
        await performSelectedVehicleRefresh(loading: .drives) { vin, generation in
            let page = try await apiClient.drives(vin: vin, limit: limit, includeRoute: false)
            try validateReadResult(for: vin, generation: generation)
            mergeRecentDrives(page.data, for: vin)
            return page.requestID
        }
    }

    func refreshRoute(for drive: FleetDriveSession, maxPoints: Int = 500) async {
        guard !drive.sessionID.isEmpty,
              drive.startedAt > 0,
              let endedAt = drive.endedAt,
              endedAt > drive.startedAt,
              maxPoints > 0 else {
            return
        }

        let generation = sessionGeneration
        do {
            let page = try await apiClient.driveRoute(
                sessionID: drive.sessionID,
                startTime: drive.startedAt,
                endTime: endedAt,
                limit: nil,
                maxPoints: maxPoints
            )
            try validateReadResult(for: drive.vin, generation: generation, requiresSelection: false)
            let normalizedRoute = FleetDataNormalizer.routePoints(page.data, limit: maxPoints)
            if !normalizedRoute.isEmpty, let sessionID = FleetDataNormalizer.normalizedString(drive.sessionID) {
                driveRoutesBySessionID[sessionID] = normalizedRoute
                if let index = recentDrives.firstIndex(where: { $0.sessionID == sessionID }) {
                    var updatedDrive = recentDrives[index]
                    updatedDrive.route = normalizedRoute
                    if let normalized = FleetDataNormalizer.driveSessions([updatedDrive]).first {
                        recentDrives[index] = normalized
                    }
                }
            }
            await recordRefreshSuccess(requestID: page.requestID)
        } catch {
            if generation == sessionGeneration, selectedVehicle?.vin == drive.vin,
               !Task.isCancelled, !(error is CancellationError) {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    var supportsContinuousHistory: Bool {
        provider == .tessie || FleetSandboxStore.shared.mode() == .demoVehicle
    }

    func refreshSelectedVehicleTelemetry(limit: Int = 100) async {
        guard supportsContinuousHistory, let vin = selectedVehicle?.vin else {
            return
        }

        let generation = sessionGeneration
        beginLoading(.telemetry)
        defer {
            if generation == sessionGeneration { finishLoading(.telemetry) }
        }

        async let series = telemetrySeries(for: vin, limit: limit)

        var didRefresh = false
        var latestRequestID: String?
        var latestErrorMessage: String?

        do {
            let page = try await apiClient.locations(vin: vin, startTime: nil, endTime: nil, limit: limit)
            try validateReadResult(for: vin, generation: generation)
            locationHistoryByVIN[vin] = FleetDataNormalizer.routePoints(page.data, limit: limit)
            latestRequestID = page.requestID ?? latestRequestID
            didRefresh = true
        } catch {
            guard generation == sessionGeneration, selectedVehicle?.vin == vin,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            latestErrorMessage = error.localizedDescription
        }

        do {
            let page = try await series
            try validateReadResult(for: vin, generation: generation)
            telemetrySeriesByVIN[vin] = FleetDataNormalizer.telemetrySeries(page.data, limit: limit)
            latestRequestID = page.requestID ?? latestRequestID
            didRefresh = true
        } catch {
            guard generation == sessionGeneration, selectedVehicle?.vin == vin,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            latestErrorMessage = error.localizedDescription
        }

        if didRefresh {
            await recordRefreshSuccess(requestID: latestRequestID)
        }
        if let latestErrorMessage, generation == sessionGeneration, selectedVehicle?.vin == vin {
            lastErrorMessage = latestErrorMessage
        }
    }

    private func telemetrySeries(for vin: String, limit: Int) async throws -> (data: [FleetTelemetrySeriesPoint], requestID: String?) {
        let page = try await apiClient.telemetrySeries(
            vin: vin, topic: nil, startTime: nil, endTime: nil,
            limit: limit, maxPoints: limit, fields: []
        )
        return (page.data, page.requestID)
    }

    func exportSelectedVehicleRawData() async {
        guard let vin = selectedVehicle?.vin, !isExportingRawData else {
            return
        }

        let generation = sessionGeneration
        isExportingRawData = true
        rawDataExportURL = nil
        rawDataExportMessage = "Exporting raw \(provider.displayName) data."
        defer {
            if generation == sessionGeneration { isExportingRawData = false }
        }

        do {
            let export = try await apiClient.rawVehicleDataExport(vin: vin)
            try validateReadResult(for: vin, generation: generation)
            let exportURL = try await FleetRawDataExporter.write(export)
            guard generation == sessionGeneration, selectedVehicle?.vin == vin, !Task.isCancelled else {
                await FleetRawDataExporter.discard(exportURL)
                throw CancellationError()
            }

            let summary = FleetRawDataExporter.summary(for: export)
            rawDataExportURL = exportURL
            rawDataExportMessage = summary.message
            lastErrorMessage = nil
            lastRequestID = summary.latestRequestID ?? lastRequestID
        } catch {
            guard generation == sessionGeneration else { return }
            if Task.isCancelled || error is CancellationError || selectedVehicle?.vin != vin {
                rawDataExportMessage = "Export cancelled."
                return
            }
            let message = error.localizedDescription
            lastErrorMessage = message
            rawDataExportMessage = message
        }
    }

    // MARK: - Snapshot & Cache Hydration

    func applySnapshotState(_ state: FleetCachedState, isCached: Bool) {
        applyNormalizedSnapshot(state.normalizedForHydration(isCached: isCached), isCached: isCached)
    }

    private func applyNormalizedSnapshot(_ state: FleetCachedState, isCached: Bool) {
        activeCharging = state.activeCharging
        activeDrivesByVIN = state.activeDrivesByVIN
        cacheDate = state.savedAt
        capabilities = state.capabilities
        cursor = state.cursor
        driveRoutesBySessionID = state.driveRoutesBySessionID
        isShowingCachedData = isCached
        lastRefreshDate = state.savedAt
        lastRequestID = nil
        locationHistoryByVIN = state.locationHistoryByVIN
        recentDrives = state.recentDrives
        selectedVIN = state.selectedVIN
        softwareUpdatesByVIN = state.softwareUpdatesByVIN
        telemetrySeriesByVIN = state.telemetrySeriesByVIN
        user = state.user
        vehicles = state.vehicles
        loadState = .loaded
        keepValidSelectionOrSelectFirst()
    }

    // MARK: - Private Coordination & Execution Helpers

    private func validateReadResult(for vin: String, generation: Int, requiresSelection: Bool = true) throws {
        try Task.checkCancellation()
        let isAvailable = requiresSelection ? selectedVehicle?.vin == vin : vehicles.contains { $0.vin == vin }
        guard generation == sessionGeneration, isAvailable else {
            throw CancellationError()
        }
    }

    @discardableResult
    private func performSelectedVehicleRefresh(
        loading kind: LoadingKind? = nil,
        operation: (String, Int) async throws -> String?
    ) async -> Bool {
        guard let vin = selectedVehicle?.vin else { return false }
        let generation = sessionGeneration

        if let kind {
            beginLoading(kind)
        }
        defer {
            if let kind, generation == sessionGeneration {
                finishLoading(kind)
            }
        }

        do {
            let requestID = try await operation(vin, generation)
            try validateReadResult(for: vin, generation: generation)
            await recordRefreshSuccess(requestID: requestID)
            return true
        } catch {
            if generation == sessionGeneration, selectedVehicle?.vin == vin,
               !Task.isCancelled, !(error is CancellationError) {
                lastErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func performSoftwareMutation(
        progressMessage: String,
        successMessage: String,
        operation: (String) async throws -> FleetAPIPage<[String: JSONValue]>
    ) async -> Bool {
        guard let vin = selectedVehicle?.vin, !isMutatingSoftware else {
            return false
        }

        let generation = sessionGeneration
        isMutatingSoftware = true
        softwareActionMessage = progressMessage
        defer {
            if generation == sessionGeneration { isMutatingSoftware = false }
        }

        do {
            let page = try await operation(vin)
            guard generation == sessionGeneration, selectedVehicle?.vin == vin else { return true }
            lastErrorMessage = nil
            lastRequestID = page.requestID ?? lastRequestID
            softwareActionMessage = successMessage
            let scope = spotlightRosterScope
            let readings = await FleetAPIClient.withSharedVehicleState(for: vin) {
                _ = await self.refreshSelectedVehicleSoftware(forceRefresh: true)
            }
            if let scope, generation == sessionGeneration, selectedVehicle?.vin == vin, scope == spotlightRosterScope {
                publishSpotlight(readings: readings, scope: scope)
            }
            return true
        } catch {
            guard generation == sessionGeneration, selectedVehicle?.vin == vin else { return false }
            let message = error.localizedDescription
            lastErrorMessage = message
            softwareActionMessage = message
            return false
        }
    }

    private func recordRefreshSuccess(requestID: String?) async {
        lastErrorMessage = nil
        lastRequestID = requestID ?? lastRequestID
        lastRefreshDate = Date()
        if !Self.batchesCacheWrites {
            await saveCurrentState()
        }
    }

    private func beginLoading(_ kind: LoadingKind) {
        loadingCounts[kind, default: 0] += 1
        setLoading(true, for: kind)
    }

    private func finishLoading(_ kind: LoadingKind) {
        let remainingCount = max(loadingCounts[kind, default: 0] - 1, 0)
        loadingCounts[kind] = remainingCount == 0 ? nil : remainingCount
        setLoading(remainingCount > 0, for: kind)
    }

    private func setLoading(_ isLoading: Bool, for kind: LoadingKind) {
        switch kind {
        case .activeDrive:
            isLoadingActiveDrive = isLoading
        case .charging:
            isLoadingCharging = isLoading
        case .drives:
            isLoadingDrives = isLoading
        case .software:
            isLoadingSoftware = isLoading
        case .telemetry:
            isLoadingTelemetry = isLoading
        }
    }

    private func pollFleetData(every interval: TimeInterval) async {
        while !Task.isCancelled {
            await refreshIfNeededForPolling()

            do {
                try await Task.sleep(for: .seconds(max(interval, 0)))
            } catch {
                return
            }
        }
    }

    private func refreshIfNeededForPolling() async {
        guard !isRefreshing, !loadState.isLoading else {
            return
        }

        if vehicles.isEmpty {
            await loadInitialDataIfNeeded()
            return
        }

        if let lastRosterRefresh, Date().timeIntervalSince(lastRosterRefresh) < 15 {
            return
        }

        await refresh()
    }

    private func refreshSelectedVehicleDetails(onlyMissing: Bool = false) async {
        let generation = sessionGeneration
        let scope = spotlightRosterScope
        var readings: FleetSpotlightIndexer.DashboardReadings?
        if let vin = selectedVehicle?.vin {
            let steps: [() async -> Void] = [
                {
                    if !onlyMissing || self.selectedVehicle?.latest?.tires == nil {
                        await self.refreshSelectedVehicleLive()
                    }
                },
                {
                    if !onlyMissing || self.activeDrivesByVIN[vin] == nil {
                        await self.refreshSelectedVehicleActiveDrive()
                    }
                },
                { await self.refreshSelectedVehicleChargingSessions() },
                {
                    if onlyMissing || self.selectedVehicleSoftwareUpdate?.releaseNotesCount == nil {
                        await self.refreshSelectedVehicleSoftware()
                    }
                },
                {
                    if !onlyMissing || self.selectedVehicleRecentDrives.isEmpty
                        || self.selectedVehicleRecentDrives.contains(where: self.needsDriveDetails) {
                        await self.refreshSelectedVehicleDrives()
                    }
                }
            ]
            readings = await Self.$batchesCacheWrites.withValue(true) {
                await FleetAPIClient.withSharedVehicleState(for: vin) {
                    for step in steps {
                        guard !Task.isCancelled, generation == self.sessionGeneration,
                              self.selectedVehicle?.vin == vin else { return }
                        await step()
                    }
                }
            }
        }
        if generation == sessionGeneration, !Task.isCancelled {
            if let scope, !isShowingCachedData, scope == spotlightRosterScope {
                publishSpotlight(readings: readings, scope: scope)
            }
            await saveCurrentState()
        }
    }

    private func publishSpotlight(readings: FleetSpotlightIndexer.DashboardReadings?, scope: String) {
        let checksProviderPermissions = provider == .teslascope && FleetSandboxStore.shared.mode() != .demoVehicle
        let roster = vehicles.map {
            FleetVehicleInfo(vin: $0.vin, displayName: $0.displayName, vehicleTag: $0.vehicleTag,
                             carType: $0.latest?.vehicleConfiguration?.carType,
                             exteriorColor: $0.latest?.vehicleConfiguration?.exteriorColor,
                             hasSeatCooling: $0.latest?.vehicleConfiguration?.hasSeatCooling,
                             canActuateTrunks: $0.latest?.vehicleConfiguration?.canActuateTrunks,
                             canAcceptNavigationRequests: $0.latest?.vehicleConfiguration?.canAcceptNavigationRequests,
                             allowsVehicleCommands: checksProviderPermissions ? $0.permissions.contains("vehicle_commands") : nil,
                             allowsChargingCommands: checksProviderPermissions ? $0.permissions.contains("charging_commands") : nil)
        }
        Task(priority: .utility) { await FleetSpotlightIndexer.synchronize(vehicles: roster, readings: readings, scope: scope) }
    }

    private func needsDriveDetails(_ drive: FleetDriveSession) -> Bool {
        drive.route.isEmpty && (drive.distanceMiles == nil || drive.avgSpeedMPH == nil || drive.maxSpeedMPH == nil)
    }

    // MARK: - Private State Merging & Persistence

    private func hydrateFromCacheIfAvailable(generation: Int) async {
        guard vehicles.isEmpty, FleetSandboxStore.shared.mode() != .demoVehicle else {
            return
        }

        guard let cachedState = try? await Self.loadCachedSnapshot(from: cache),
              generation == sessionGeneration, !Task.isCancelled, vehicles.isEmpty,
              !loadState.isLoading, FleetSandboxStore.shared.mode() != .demoVehicle else { return }
        applyNormalizedSnapshot(cachedState, isCached: true)
    }

    @concurrent private static func loadCachedSnapshot(from cache: any FleetDataCaching) async throws -> FleetCachedState? {
        let snapshot = try await cache.load()
        try Task.checkCancellation()
        return snapshot?.normalizedForHydration(isCached: true)
    }

    private func applyBootstrap(_ bootstrap: FleetBootstrap, cursor: Int64?, requestID: String?, isCached: Bool) {
        activeCharging = FleetDataNormalizer.chargeSessions(bootstrap.activeCharging)
        capabilities = FleetDataNormalizer.capabilities(bootstrap.capabilities)
        self.cursor = cursor
        cacheDate = nil
        isShowingCachedData = isCached
        lastRefreshDate = Date()
        lastRosterRefresh = lastRefreshDate
        lastRequestID = requestID
        recentDrives = FleetDataNormalizer.driveSessions(bootstrap.recentDrives)
        user = FleetDataNormalizer.user(bootstrap.user)
        vehicles = FleetDataNormalizer.vehicles(bootstrap.vehicles)
        mergeSoftwareUpdates(FleetDataNormalizer.softwareUpdatesByVIN(from: vehicles))

        keepValidSelectionOrSelectFirst()
    }

    private func applyVehicleRoster(_ roster: [FleetVehicle]) {
        let previousSnapshots = latestSnapshotsByVIN
        let nextVehicles = FleetDataNormalizer.vehicles(roster)
        let currentVINs = Set(nextVehicles.map(\.vin))
        let removedVINs = Set(vehicles.map(\.vin)).subtracting(currentVINs)

        vehicles = nextVehicles.map { vehicle in
            guard let previous = previousSnapshots[vehicle.vin] else {
                return vehicle
            }
            if let previousTimestamp = previous.updatedAt,
               (vehicle.latest?.updatedAt ?? 0) < previousTimestamp {
                var updatedVehicle = vehicle
                updatedVehicle.latest = previous
                return updatedVehicle
            }
            if vehicle.latest?.tires == nil, let previousTires = previous.tires {
                var updatedVehicle = vehicle
                updatedVehicle.latest?.tires = previousTires
                return updatedVehicle
            }
            return vehicle
        }
        for vehicle in vehicles {
            if let snapshot = vehicle.latest { reconcilePendingControls(with: snapshot) }
        }
        if !removedVINs.isEmpty {
            let removedSessionIDs = Set(recentDrives.lazy.filter { removedVINs.contains($0.vin) }.map(\.sessionID))
                .union(activeDrivesByVIN.values.lazy.filter { removedVINs.contains($0.vin) }.map(\.sessionID))
            driveRoutesBySessionID = driveRoutesBySessionID.filter { sessionID, _ in
                !removedSessionIDs.contains(sessionID) && !removedVINs.contains { vin in
                    sessionID.hasPrefix("\(vin):")
                        || sessionID.hasPrefix("drive:\(vin):")
                        || sessionID == "active:\(vin)"
                }
            }
            activeCharging.removeAll { removedVINs.contains($0.vin) }
            recentDrives.removeAll { removedVINs.contains($0.vin) }
            for vin in removedVINs {
                pendingControlsByVIN.removeValue(forKey: vin)
                activeDrivesByVIN.removeValue(forKey: vin)
                softwareUpdatesByVIN.removeValue(forKey: vin)
                locationHistoryByVIN.removeValue(forKey: vin)
                telemetrySeriesByVIN.removeValue(forKey: vin)
            }
        }

        mergeSoftwareUpdates(FleetDataNormalizer.softwareUpdatesByVIN(from: vehicles))
        keepValidSelectionOrSelectFirst()
    }

    private func keepValidSelectionOrSelectFirst() {
        if let selectedVIN, vehicles.contains(where: { $0.vin == selectedVIN }) {
            return
        }
        selectedVIN = vehicles.first?.vin
    }

    private func refreshCapabilitiesIfNeeded(generation: Int) async {
        guard capabilities == nil else {
            return
        }

        do {
            let page = try await apiClient.capabilities()
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            capabilities = FleetDataNormalizer.capabilities(page.data)
            lastRequestID = page.requestID ?? lastRequestID
        } catch {
            if generation == sessionGeneration, !Task.isCancelled { lastErrorMessage = error.localizedDescription }
        }
    }

    private func mergeChargingSessions(_ sessions: [FleetChargeSession], for vin: String) {
        let normalizedSessions = FleetDataNormalizer.chargeSessions(sessions, fallbackVIN: vin)
        let otherSessions = activeCharging.filter { $0.vin != vin }
        activeCharging = otherSessions.isEmpty ? normalizedSessions : FleetDataNormalizer.chargeSessions(otherSessions + normalizedSessions)
    }

    private func mergeRecentDrives(_ drives: [FleetDriveSession], for vin: String) {
        let normalizedDrives = FleetDataNormalizer.driveSessions(drives, fallbackVIN: vin)
        for drive in normalizedDrives where !drive.route.isEmpty {
            driveRoutesBySessionID[drive.sessionID] = drive.route
        }

        let otherDrives = recentDrives.filter { $0.vin != vin }
        recentDrives = otherDrives.isEmpty ? normalizedDrives : FleetDataNormalizer.driveSessions(otherDrives + normalizedDrives)
    }

    private func mergeSoftwareUpdates(_ updates: [String: FleetSoftwareUpdate]) {
        if !updates.isEmpty { softwareUpdatesByVIN.mergeNormalizedUpdates(updates) }
    }

    private func mergeActiveDrive(_ drive: FleetActiveDriveSession, for vin: String) {
        guard let normalizedDrive = FleetDataNormalizer.activeDrive(drive, fallbackVIN: vin) else {
            activeDrivesByVIN.removeValue(forKey: vin)
            return
        }

        guard normalizedDrive.active else {
            activeDrivesByVIN.removeValue(forKey: normalizedDrive.vin.isEmpty ? vin : normalizedDrive.vin)
            return
        }

        activeDrivesByVIN[normalizedDrive.vin] = normalizedDrive
        if let latest = normalizedDrive.latest {
            mergeLatestSnapshots([latest])
        }
        if !normalizedDrive.sessionID.isEmpty, !normalizedDrive.route.isEmpty {
            driveRoutesBySessionID[normalizedDrive.sessionID] = normalizedDrive.route
        }
    }

    private func mergeLatestSnapshots(_ snapshots: [FleetLatestSnapshot]) {
        var updates = Dictionary(uniqueKeysWithValues: FleetDataNormalizer.latestSnapshots(snapshots).map { ($0.vin, $0) })
        var softwareUpdates: [String: FleetSoftwareUpdate] = [:]
        for index in vehicles.indices {
            guard !updates.isEmpty else { break }
            let previous = vehicles[index].latest
            guard var snapshot = updates.removeValue(forKey: vehicles[index].vin),
                  (snapshot.updatedAt ?? 0) >= (previous?.updatedAt ?? 0) else { continue }
            if snapshot.tires == nil { snapshot.tires = previous?.tires }
            if let software = snapshot.software { softwareUpdates[snapshot.vin] = software }
            vehicles[index].latest = snapshot
            reconcilePendingControls(with: snapshot)
        }
        mergeSoftwareUpdates(softwareUpdates)
    }

    private func saveCurrentState() async {
        guard FleetSandboxStore.shared.mode() != .demoVehicle else {
            return
        }
        let savedAt = Date()
        let generation = sessionGeneration
        let state = FleetCachedState(
            activeCharging: activeCharging,
            activeDrivesByVIN: activeDrivesByVIN,
            capabilities: capabilities,
            cursor: cursor,
            driveRoutesBySessionID: driveRoutesBySessionID,
            locationHistoryByVIN: locationHistoryByVIN.filter { !$0.value.isEmpty },
            recentDrives: recentDrives,
            savedAt: savedAt,
            selectedVIN: selectedVIN,
            softwareUpdatesByVIN: softwareUpdatesByVIN,
            telemetrySeriesByVIN: telemetrySeriesByVIN.filter { !$0.value.isEmpty },
            user: user,
            vehicles: vehicles
        )

        do {
            try await cache.save(state)
            if generation == sessionGeneration { cacheDate = savedAt }
        } catch {
            // Cache writes should never block live fleet data from rendering.
        }
    }
}
