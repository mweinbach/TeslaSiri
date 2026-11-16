import AppIntents
import Foundation
import OSLog

/// Intent-facing service. Resolves the target vehicle and exposes the reads and
/// control actions the intents need. Reads are side-effect-free (safe for
/// repeatedly performed snippet intents); writes are used by control intents.
public struct FleetIntentService: Sendable {
    @TaskLocal static var testingOverride: FleetIntentService?
    @TaskLocal public static var sandboxConfirmationRecorder: (@Sendable (String) -> Void)?

    private let client: FleetIntentClient
    private let tokenStore: FleetSharedTokenStore
    private let sandbox: FleetSandboxStore?
    private let credentialFingerprint: String?
    private let initialSessionScope: String?

    public init(
        client: FleetIntentClient = FleetIntentClient(),
        tokenStore: FleetSharedTokenStore? = nil,
        sandbox: FleetSandboxStore? = nil
    ) {
        self.client = client
        self.tokenStore = tokenStore ?? client.tokenStore
        self.sandbox = sandbox
        let fingerprint = sandbox?.mode() == .demoVehicle ? nil : client.tokenStore.accessToken(for: client.provider).map(FleetSharedTokenStore.fingerprint(for:))
        self.credentialFingerprint = fingerprint
        self.initialSessionScope = Self.scope(client: client, sandbox: sandbox, fingerprint: fingerprint)
    }

    public static func make() -> FleetIntentService {
        testingOverride ?? FleetIntentService(sandbox: .shared)
    }

    private var sandboxMode: FleetSandboxMode {
        sandbox?.mode() ?? .live
    }

    var usesTeslascope: Bool { sandboxMode != .demoVehicle && client.provider == .teslascope }

    var appGroupIdentifier: String { sandbox?.appGroup ?? client.tokenStore.appGroup }

    /// Opaque identity shared by the app and extension. Changes when credentials or sandbox mode change.
    public var sessionScopeID: String? {
        let current = Self.scope(client: client, sandbox: sandbox, fingerprint: credentialFingerprint)
        return current == initialSessionScope ? current : nil
    }

    private static func scope(client: FleetIntentClient, sandbox: FleetSandboxStore?, fingerprint: String?) -> String? {
        let mode = sandbox?.sessionScope ?? "live"
        if sandbox?.mode() == .demoVehicle { return "demo.\(mode)" }
        guard let fingerprint, client.tokenStore.provider == client.provider else { return nil }
        return "\(client.tokenStore.sessionScope(fingerprint: fingerprint)).\(mode)"
    }

    /// Recheck the actual Keychain credential at request construction. Cache hits only check the shared generations.
    private func withSession<Result>(_ work: () async throws -> Result) async throws -> Result {
        _ = try validatedScope()
        let result = try await FleetIntentClient.$validateRequest.withValue({ token in
            guard FleetSharedTokenStore.fingerprint(for: token) == credentialFingerprint,
                  sessionScopeID != nil else { throw FleetKitError.sessionExpired }
        }) {
            try await work()
        }
        _ = try validatedScope()
        return result
    }

    private func validatedScope() throws -> String {
        guard let initialSessionScope else { throw FleetKitError.notSignedIn }
        guard sessionScopeID == initialSessionScope else { throw FleetKitError.sessionExpired }
        return initialSessionScope
    }

    // MARK: - Resolution

    public func defaultVehicle(in vehicles: [FleetVehicleInfo]) -> FleetVehicleInfo? {
        if let selected = tokenStore.selectedVIN(), let vehicle = vehicles.first(where: { $0.vin == selected }) {
            return vehicle
        }
        return vehicles.first
    }

    public func resolvedVehicle(_ requestedVIN: String?) async throws -> FleetVehicleInfo {
        let roster = try await vehicles(requiring: requestedVIN)
        if let requestedVIN {
            guard let vehicle = roster.first(where: { $0.vin == requestedVIN }) else {
                throw FleetKitError.api("That vehicle is no longer available on this account.")
            }
            return vehicle
        }
        guard let vehicle = defaultVehicle(in: roster) else {
            throw FleetKitError.api("No Tesla vehicles were found on your account.")
        }
        return vehicle
    }

    // MARK: - Reads

    public func vehicles() async throws -> [FleetVehicleInfo] {
        try await vehicles(requiring: nil)
    }

    private func vehicles(requiring vin: String?) async throws -> [FleetVehicleInfo] {
        let scope = try validatedScope()
        if let sandbox, sandbox.mode() == .demoVehicle {
            return [sandbox.demoState().vehicleInfo]
        }
        return try await withSession { try await client.vehicles(requiring: vin, scope: scope) }
    }

    public func snapshot(vin: String) async throws -> FleetSnapshotInfo {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return sandbox.demoState().snapshotInfo
        }
        return try await withSession { try await client.snapshot(vin: vin) }
    }

    func snapshot(for vehicle: FleetVehicleInfo, topics: [VehicleInfoTopic]) async throws -> FleetSnapshotInfo {
        _ = try validatedScope()
        if let sandbox, sandbox.mode() == .demoVehicle { return sandbox.demoState().snapshotInfo }
        if let charge = vehicle.rosterCharge, charge.isRecentRosterObservation,
           !topics.isEmpty, topics.allSatisfy({ topic in
               switch topic {
               case .battery: charge.batteryLevel != nil
               case .range: charge.batteryRangeMiles != nil
               default: false
               }
           }) {
            return charge
        }
        return try await withSession { try await client.snapshot(vin: vehicle.vin, topics: topics) }
    }

    public func batterySnapshotForReminder(for vehicle: FleetVehicleInfo, maxAge: TimeInterval) async throws -> FleetSnapshotInfo? {
        let charge = try await snapshot(for: vehicle, topics: [.charging])
        guard usesTeslascope else { return charge }
        guard let date = charge.updatedAtDate, let chargingState = charge.chargingState,
              !chargingState.isEmpty else { return nil }
        let age = Date.now.timeIntervalSince(date)
        return age >= 0 && age <= maxAge ? charge : nil
    }

    func cachedClimateSnapshot(vin: String) async -> FleetSnapshotInfo? {
        guard let scope = try? validatedScope() else { return nil }
        if let sandbox, sandbox.mode() == .demoVehicle {
            let state = sandbox.demoState()
            return state.vehicleInfo.vin == vin ? state.snapshotInfo : nil
        }
        guard let climate = await client.cachedVehicle(vin: vin, scope: scope)?.rosterClimate,
              climate.isRecentRosterObservation, sessionScopeID == scope else { return nil }
        return climate
    }

    func snapshotAndSoftware(vin: String) async throws -> (snapshot: FleetSnapshotInfo, software: FleetSoftwareInfo) {
        if let sandbox, sandbox.mode() == .demoVehicle {
            let state = sandbox.demoState()
            return (state.snapshotInfo, state.softwareInfo)
        }
        return try await withSession { try await client.snapshotAndSoftware(vin: vin) }
    }

    public func units() async throws -> String? {
        if let sandbox, sandbox.mode() == .demoVehicle { return "imperial" }
        return try await withSession { try await client.units(scope: validatedScope()) }
    }

    public func drives(
        vin: String,
        limit: Int,
        from: Date? = nil,
        to: Date? = nil,
        tag: String? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetDriveInfo] {
        if let sandbox, sandbox.mode() == .demoVehicle {
            let normalizedTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let filtered = FleetDemoVehicleState.demoDrives(vin: vin).filter { drive in
                if let from, drive.startedAtDate < from { return false }
                if let to, drive.startedAtDate > to { return false }
                if let normalizedTag, !normalizedTag.isEmpty {
                    guard drive.tag?.lowercased().contains(normalizedTag) == true else { return false }
                }
                return true
            }
            return Array(filtered.prefix(max(limit, 0)))
        }
        return try await withSession { try await client.drives(vin: vin, limit: limit, from: from, to: to, tag: tag, requireCompleteRows: requireCompleteRows) }
    }

    /// Teslascope list rows omit fields that are only available on the session detail endpoint.
    func driveDetails(_ summary: DriveEntity) async throws -> DriveEntity {
        try validateHistoryID(summary.id, vin: summary.vin)
        guard usesTeslascope else { return summary }
        let record = try await withSession { try await client.driveDetails(vin: summary.vin, id: summary.id) }
        return record.map(DriveEntity.init(info:)) ?? summary
    }

    func chargeDetails(_ summary: ChargeSessionEntity) async throws -> ChargeSessionEntity {
        try validateHistoryID(summary.id, vin: summary.vin)
        guard usesTeslascope else { return summary }
        let record = try await withSession { try await client.chargeDetails(vin: summary.vin, id: summary.id) }
        return record.map(ChargeSessionEntity.init(info:)) ?? summary
    }

    private func validateHistoryID(_ id: String, vin: String) throws {
        if id.hasPrefix("\(vin):teslascope:") != usesTeslascope {
            throw FleetKitError.api("That session belongs to a different vehicle provider.")
        }
    }

    public func drivePath(
        vin: String,
        driveID: String? = nil,
        from: Date,
        to: Date,
        maxPoints: Int = 72
    ) async throws -> [FleetDriveRoutePoint] {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return FleetDemoVehicleState.demoDrivePath(driveID: driveID, from: from, to: to)
        }
        return try await withSession { try await client.drivePath(vin: vin, driveID: driveID, from: from, to: to, maxPoints: maxPoints) }
    }

    public func charges(
        vin: String,
        limit: Int,
        from: Date? = nil,
        to: Date? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetChargeInfo] {
        if let sandbox, sandbox.mode() == .demoVehicle {
            let filtered = FleetDemoVehicleState.demoCharges(vin: vin).filter { charge in
                if let from, charge.startedAtDate < from { return false }
                if let to, charge.startedAtDate > to { return false }
                return true
            }
            return Array(filtered.prefix(max(limit, 0)))
        }
        return try await withSession { try await client.charges(vin: vin, limit: limit, from: from, to: to, requireCompleteRows: requireCompleteRows) }
    }

    public func batteryHealth(vin: String) async throws -> FleetBatteryHealthInfo {
        if let sandbox, sandbox.mode() == .demoVehicle {
            let state = sandbox.demoState()
            return FleetDemoVehicleState.demoBatteryHealth(vin: vin, odometerMiles: state.odometerMiles)
        }
        return try await withSession { try await client.batteryHealth(vin: vin) }
    }

    public func consumptionSinceCharge(vin: String) async throws -> FleetConsumptionInfo {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return FleetDemoVehicleState.demoConsumption()
        }
        return try await withSession { try await client.consumptionSinceCharge(vin: vin) }
    }

    public func software(vin: String) async throws -> FleetSoftwareInfo {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return sandbox.demoState().softwareInfo
        }
        return try await withSession { try await client.software(vin: vin) }
    }

    public func releaseNotes(vin: String, version: String) async throws -> [FleetReleaseNoteInfo] {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return FleetDemoVehicleState.demoReleaseNotes(version: version)
        }
        return try await withSession { try await client.releaseNotes(vin: vin, version: version) }
    }

    public func controlActions(for vehicle: FleetVehicleInfo? = nil) async throws -> FleetControlActionsInfo {
        if let sandbox, sandbox.mode() == .demoVehicle {
            return FleetDemoVehicleState.supportedControlActions
        }
        if usesTeslascope {
            let target: FleetVehicleInfo
            if let vehicle { target = vehicle } else { target = try await resolvedVehicle(nil) }
            return TeslascopeClient.controlActions(for: target)
        }
        return try await client.controlActions()
    }

    // MARK: - Writes

    /// Checks membership again at dispatch. A just-resolved VIN reuses the same roster.
    private func dispatch(
        vin: String,
        validate: (FleetVehicleInfo) async throws -> Void,
        simulate: (FleetSandboxStore, String) -> Void,
        send: () async throws -> Void
    ) async throws {
        let scope = try validatedScope()
        let target = try await resolvedVehicle(vin)
        try await validate(target)
        guard sessionScopeID == scope else { throw FleetKitError.sessionExpired }
        if let sandbox, sandbox.mode().interceptsWrites {
            simulate(sandbox, target.name)
            return
        }
        try await withSession(send)
    }

    public func runControl(
        action: String,
        vin: String,
        params: [String: FleetControlValue] = [:],
        humanName: String
    ) async throws {
        try await dispatch(vin: vin) { target in
            let available = try await controlActions(for: target)
            guard available.supports(action) else { throw FleetKitError.unsupportedAction(humanName) }
        } simulate: { sandbox, name in
            sandbox.recordSimulatedControl(action: action, vin: vin, vehicleName: name, params: params, source: "Siri")
        } send: {
            try await client.runControl(action: action, vin: vin, params: params)
            if let scope = initialSessionScope {
                await client.invalidateRosterTelemetry(vin: vin, scope: scope, action: action)
            }
        }
        if action == "auto_conditioning_start" || action == "auto_conditioning_stop" || action == "set_temps",
           let scope = initialSessionScope, scope == sessionScopeID {
            let target = (params["driver_temp"] ?? params["passenger_temp"]).flatMap { Double($0.queryValue) }
            recordClimateControl(action, vin: vin, targetCelsius: target)
        }
        FleetKitLog.intents.notice("Control '\(action, privacy: .public)' completed for \(FleetKitLog.vin(vin), privacy: .public) [\(self.sandboxMode.rawValue, privacy: .public)]")
    }

    func checkSoftwareCommand(for vehicle: FleetVehicleInfo, installAfter delay: Int?) throws {
        guard usesTeslascope else { return }
        guard let delay else { throw FleetKitError.api("Teslascope does not support canceling software updates.") }
        guard delay == 0 else { throw FleetKitError.api("Teslascope can start a software update immediately. It cannot schedule one for later.") }
        guard vehicle.allowsVehicleCommands != false else {
            throw FleetKitError.api("Vehicle command access is disabled on this linked Tesla account.")
        }
    }

    public func installSoftwareUpdate(vin: String, offsetSec: Int) async throws {
        try await dispatch(vin: vin) { target in
            try checkSoftwareCommand(for: target, installAfter: offsetSec)
        } simulate: { sandbox, name in
            sandbox.recordSimulatedSoftwareAction(isInstall: true, vin: vin, vehicleName: name, offsetSec: offsetSec, source: "Siri")
        } send: {
            try await client.installSoftwareUpdate(vin: vin, offsetSec: offsetSec)
        }
    }

    public func cancelSoftwareUpdate(vin: String) async throws {
        try await dispatch(vin: vin) { target in
            try checkSoftwareCommand(for: target, installAfter: nil)
        } simulate: { sandbox, name in
            sandbox.recordSimulatedSoftwareAction(isInstall: false, vin: vin, vehicleName: name, source: "Siri")
        } send: {
            try await client.cancelSoftwareUpdate(vin: vin)
        }
    }
}

extension AppIntent {
    func confirmWithSafetyGate(dialog: IntentDialog) async throws {
        let canAutoApprove = FleetIntentService.testingOverride != nil
            || FleetSandboxStore.shared.mode() != .live
        if canAutoApprove, let recorder = FleetIntentService.sandboxConfirmationRecorder {
            recorder(String(describing: dialog))
            return
        }
        try await requestConfirmation(dialog: dialog)
    }
}

extension LongRunningIntent {
    func performSandboxAwareBackgroundTask(_ work: @escaping @Sendable () async throws -> Void) async throws {
        let canRunInline = FleetIntentService.testingOverride != nil
            || FleetSandboxStore.shared.mode() != .live
        if canRunInline, FleetIntentService.sandboxConfirmationRecorder != nil {
            try await work()
            return
        }
        try await performBackgroundTask(operation: work)
    }
}

