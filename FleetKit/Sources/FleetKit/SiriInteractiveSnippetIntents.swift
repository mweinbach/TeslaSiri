import AppIntents
import Foundation
import SwiftUI

// MARK: - Interactive Drive Route Snippet Intent

/// Presents an interactive Apple Maps drive route widget in Siri, supporting live
/// Map/Satellite toggling and stepping through multiple matched drives in place.
public struct DriveRouteSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Drive Route Card"
    public static let isDiscoverable = false

    @Parameter(title: "Drives")
    public var drives: [DriveEntity]

    @Parameter(title: "Vehicle Name")
    public var vehicleName: String

    @Parameter(title: "Session Key")
    public var sessionKey: String

    public init() {
        self.drives = []
        self.vehicleName = "My Car"
        self.sessionKey = "default"
    }

    public init(drives: [DriveEntity], vehicleName: String, sessionKey: String = "latest") {
        self.drives = drives
        self.vehicleName = vehicleName
        self.sessionKey = sessionKey
        SiriSnippetStateStore.shared.setSelectedDriveIndex(0, for: sessionKey)
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard !drives.isEmpty else {
            return .result(
                view: EmptyDriveSnippetView(vehicleName: vehicleName)
            )
        }

        let store = SiriSnippetStateStore.shared
        let index = store.selectedDriveIndex(for: sessionKey, count: drives.count)
        let activeDrive = drives[index]
        let style = store.mapStyle(for: "drive")
        let allowMap = FleetIntentService.testingOverride == nil

        let mapData = await SiriMapSnapshotRenderer.renderDriveRoute(
            for: activeDrive,
            service: .make(),
            style: style,
            allowNetworkSnapshot: allowMap
        )

        return .result(
            view: DriveSnippetView(
                drive: activeDrive,
                allDrives: drives,
                selectedIndex: index,
                sessionKey: sessionKey,
                vehicleName: vehicleName,
                mapData: mapData
            )
        )
    }
}

// MARK: - Interactive Charge Session Snippet Intent

/// Presents an interactive charging session card with Apple Maps charger location,
/// battery fill bar, and multi-session stepping inside Siri.
public struct ChargeSessionSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Charging Session Card"
    public static let isDiscoverable = false

    @Parameter(title: "Sessions")
    public var sessions: [ChargeSessionEntity]

    @Parameter(title: "Vehicle Name")
    public var vehicleName: String

    @Parameter(title: "Session Key")
    public var sessionKey: String

    public init() {
        self.sessions = []
        self.vehicleName = "My Car"
        self.sessionKey = "charge-default"
    }

    public init(sessions: [ChargeSessionEntity], vehicleName: String, sessionKey: String = "charge-latest") {
        self.sessions = sessions
        self.vehicleName = vehicleName
        self.sessionKey = sessionKey
        SiriSnippetStateStore.shared.setSelectedDriveIndex(0, for: sessionKey)
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard !sessions.isEmpty else {
            return .result(
                view: EmptyChargeSnippetView(vehicleName: vehicleName)
            )
        }

        let store = SiriSnippetStateStore.shared
        let index = store.selectedDriveIndex(for: sessionKey, count: sessions.count)
        let active = sessions[index]
        let style = store.mapStyle(for: "charge")
        let allowMap = FleetIntentService.testingOverride == nil
        let accent: UInt32 = active.isSupercharger ? 0xFF3B30 : 0x30D158

        let mapData = await SiriMapSnapshotRenderer.renderLocationPin(
            latitude: active.latitude,
            longitude: active.longitude,
            fallbackPlaceQuery: active.location,
            style: style,
            accentHex: accent,
            allowNetworkSnapshot: allowMap
        )

        return .result(
            view: ChargeSessionSnippetView(
                session: active,
                allSessions: sessions,
                selectedIndex: index,
                sessionKey: sessionKey,
                vehicleName: vehicleName,
                mapData: mapData
            )
        )
    }
}

// MARK: - Interactive Cabin Climate Snippet Intent

/// The last command affecting one vehicle's climate card. App Intents can recreate
/// the snippet in a different process after a button tap.
struct ClimateCommandReceipt: Codable, Sendable {
    let sessionScope: String
    let interactionID: String
    var date: Date
    var targetCelsius: Double?
    var targetSetAt: Date?
    var running: Bool?
    var startedAt: Date?
    var summary: String
    var deliveryState: VehicleCommandDeliveryState? = nil

    var isWaking: Bool {
        deliveryState == .wakingVehicle
    }

    func recentlyStarted(at now: Date = .now, observation: FleetSnapshotInfo? = nil) -> Bool {
        guard !isWaking, running == true, let startedAt else { return false }
        if observation?.hvacOn == false, let observedAt = observation?.updatedAtDate, observedAt > startedAt {
            return false
        }
        return (0..<30).contains(now.timeIntervalSince(startedAt))
    }

    func save(vin: String, group: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: group)?.set(data, forKey: "siri.climate.receipt.\(vin)")
    }

    static func latest(vin: String, scope: String?, group: String) -> Self? {
        guard let scope,
              let data = UserDefaults(suiteName: group)?.data(forKey: "siri.climate.receipt.\(vin)"),
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              receipt.sessionScope == scope else { return nil }
        return receipt
    }
}

extension FleetIntentService {
    /// Keep climate state current across Siri tools, snippets, and dashboard controls.
    /// Creates a receipt when none exists so `ControlCarIntent` and dashboard toggles
    /// stay synchronized with `isClimateLikelyRunning(vin:)`.
    public func recordClimateControl(
        _ action: String,
        vin: String,
        targetCelsius: Double? = nil,
        deliveryState: VehicleCommandDeliveryState = .confirmed
    ) {
        guard action == "auto_conditioning_start" || action == "auto_conditioning_stop" || action == "set_temps",
              let scope = sessionScopeID else { return }
        let existing = ClimateCommandReceipt.latest(vin: vin, scope: scope, group: appGroupIdentifier)
        let now = Date.now
        var receipt = existing ?? ClimateCommandReceipt(
            sessionScope: scope,
            interactionID: UUID().uuidString,
            date: now,
            targetCelsius: nil,
            targetSetAt: nil,
            running: nil,
            startedAt: nil,
            summary: "",
            deliveryState: deliveryState
        )
        if action == "set_temps" {
            guard let targetCelsius, targetCelsius.isFinite else { return }
            receipt.targetCelsius = targetCelsius
            receipt.targetSetAt = now
            receipt.deliveryState = deliveryState
            receipt.summary = "Cabin target updated."
        } else {
            let running = action == "auto_conditioning_start"
            receipt.running = running
            receipt.date = now
            receipt.deliveryState = deliveryState
            receipt.startedAt = (running && deliveryState == .confirmed) ? now : nil
            if deliveryState == .wakingVehicle {
                receipt.summary = running
                    ? "Waking car to start climate."
                    : "Waking car to turn off climate."
            } else {
                receipt.summary = running ? "Climate is on." : "Climate is off."
            }
        }
        receipt.save(vin: vin, group: appGroupIdentifier)
        if existing != nil {
            ClimateControlSnippetIntent.reload()
        }
    }
}

public struct ClimateControlSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Cabin Climate Card"
    public static let isDiscoverable = false

    @Parameter(title: "Vehicle")
    public var vehicle: VehicleEntity

    @Parameter(title: "Applied Summary")
    public var appliedSummary: String

    @Parameter(title: "Climate Interaction")
    var interactionID: String?

    @Parameter(title: "Account and Mode")
    var sessionScope: String?

    public init() {
        self.vehicle = VehicleEntity(id: "", name: "My Car")
        self.appliedSummary = "Climate updated"
    }

    public init(vehicle: VehicleEntity, appliedSummary: String) {
        self.vehicle = vehicle
        self.appliedSummary = appliedSummary
        self.sessionScope = FleetIntentService.make().sessionScopeID
    }

    init(
        vehicle: VehicleEntity,
        appliedSummary: String,
        scope: String?,
        running: Bool?,
        targetCelsius: Double? = nil,
        deliveryState: VehicleCommandDeliveryState = .confirmed,
        confirmedStart: Bool = true,
        existingStartAnchor: Date? = nil
    ) {
        self.vehicle = vehicle
        self.appliedSummary = appliedSummary
        self.sessionScope = scope
        let service = FleetIntentService.make()
        guard let scope, scope == service.sessionScopeID else { return }
        let id = UUID().uuidString
        self.interactionID = id
        let now = Date.now
        let previous = ClimateCommandReceipt.latest(vin: vehicle.id, scope: scope, group: service.appGroupIdentifier)
        let startedAt: Date?
        if running == true, deliveryState == .confirmed {
            if confirmedStart {
                startedAt = now
            } else if let existingStartAnchor {
                startedAt = existingStartAnchor
            } else if previous?.isWaking != true, previous?.running == true {
                startedAt = previous?.startedAt
            } else {
                startedAt = nil
            }
        } else {
            startedAt = nil
        }
        ClimateCommandReceipt(
            sessionScope: scope,
            interactionID: id,
            date: now,
            targetCelsius: targetCelsius ?? previous?.targetCelsius,
            targetSetAt: targetCelsius == nil ? previous?.targetSetAt : now,
            running: running,
            startedAt: startedAt,
            summary: appliedSummary,
            deliveryState: deliveryState
        ).save(vin: vehicle.id, group: service.appGroupIdentifier)
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        let service = FleetIntentService.make()
        let scope = service.sessionScopeID
        guard let scope, sessionScope == scope else {
            throw log.failure(FleetKitError.api("The account or command mode changed. Ask for the car again."))
        }
        let snapshot = await service.cachedClimateSnapshot(vin: vehicle.id)
        guard scope == service.sessionScopeID else { throw log.failure(FleetKitError.sessionExpired) }
        let receipt = ClimateCommandReceipt.latest(vin: vehicle.id, scope: scope, group: service.appGroupIdentifier)
        let view = ClimateControlSnippetView(
            vehicle: vehicle, status: snapshot.map { VehicleStatusEntity(snapshot: $0, vehicleName: vehicle.name) },
            appliedSummary: receipt?.summary ?? appliedSummary, receipt: receipt,
            interactionID: interactionID, sessionScope: scope
        )
        log.success("climate card ready")
        return .result(view: view)
    }
}

// MARK: - Snippet In-Place Interactive Button Intents

/// Toggles Standard vs Satellite Apple Maps imagery inside Siri snippets and reloads in place.
public struct ToggleSnippetMapStyleIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Snippet Map Style"
    public static let isDiscoverable = false

    @Parameter(title: "Scope")
    public var scope: String

    public init() {
        self.scope = "drive"
    }

    public init(scope: String) {
        self.scope = scope
    }

    public func perform() async throws -> some IntentResult {
        SiriSnippetStateStore.shared.toggleMapStyle(for: scope)
        switch scope {
        case "drive": DriveRouteSnippetIntent.reload()
        case "charge": ChargeSessionSnippetIntent.reload()
        case "vehicle": GetVehicleStatusIntent.reload()
        default:
            DriveRouteSnippetIntent.reload()
            ChargeSessionSnippetIntent.reload()
            GetVehicleStatusIntent.reload()
        }
        return .result()
    }
}

/// Steps between multiple drives or charging sessions directly inside a Siri snippet card.
public struct SelectSnippetItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Select Snippet Item"
    public static let isDiscoverable = false

    @Parameter(title: "Session Key")
    public var sessionKey: String

    @Parameter(title: "Target Index")
    public var targetIndex: Int

    @Parameter(title: "Card Type")
    public var cardType: String?

    public init() {
        self.sessionKey = "latest"
        self.targetIndex = 0
    }

    public init(sessionKey: String, targetIndex: Int, cardType: String? = nil) {
        self.sessionKey = sessionKey
        self.targetIndex = targetIndex
        self.cardType = cardType
    }

    public func perform() async throws -> some IntentResult {
        SiriSnippetStateStore.shared.setSelectedDriveIndex(targetIndex, for: sessionKey)
        switch cardType {
        case "drive": DriveRouteSnippetIntent.reload()
        case "charge": ChargeSessionSnippetIntent.reload()
        default:
            DriveRouteSnippetIntent.reload()
            ChargeSessionSnippetIntent.reload()
        }
        return .result()
    }
}

/// Changes climate from a displayed card, keeping later renders on the acknowledged setting.
public struct AdjustSnippetClimateIntent: AppIntent, LongRunningIntent {
    public static let title: LocalizedStringResource = "Adjust Cabin Climate"
    public static let isDiscoverable = false

    @Parameter(title: "Vehicle")
    public var vehicle: VehicleEntity

    @Parameter(title: "Target Fahrenheit")
    public var targetFahrenheit: Double?

    @Parameter(title: "Turn Off")
    public var turnOff: Bool

    @Parameter(title: "Climate Interaction")
    var interactionID: String?

    @Parameter(title: "Account and Mode")
    var sessionScope: String?

    public init() {
        self.vehicle = VehicleEntity(id: "", name: "My Car")
        self.turnOff = false
    }

    public init(vehicle: VehicleEntity, targetFahrenheit: Double? = nil, turnOff: Bool = false) {
        self.vehicle = vehicle
        self.targetFahrenheit = targetFahrenheit
        self.turnOff = turnOff
        self.sessionScope = FleetIntentService.make().sessionScopeID
    }

    init(vehicle: VehicleEntity, targetFahrenheit: Double?, turnOff: Bool, interactionID: String?, scope: String?) {
        self.vehicle = vehicle
        self.targetFahrenheit = targetFahrenheit
        self.turnOff = turnOff
        self.interactionID = interactionID
        self.sessionScope = scope
    }

    public func perform() async throws -> some IntentResult {
        let service = FleetIntentService.make()
        guard !vehicle.id.isEmpty, let scope = service.sessionScopeID, sessionScope == scope else {
            throw FleetKitError.api("The account or command mode changed. Ask for the car again.")
        }
        let resolved = try await service.resolvedVehicle(vehicle.id)
        guard resolved.vin == vehicle.id, scope == service.sessionScopeID else {
            throw FleetKitError.api("This car is no longer available.")
        }
        let observation = await service.cachedClimateSnapshot(vin: resolved.vin)
        let previous = ClimateCommandReceipt.latest(vin: resolved.vin, scope: scope, group: service.appGroupIdentifier)
        let turnOffRequested = turnOff
        let targetF = targetFahrenheit
        let cardInteractionID = interactionID

        let startedAt: Date?
        let target: Double?
        let summary: String
        let deliveryState: VehicleCommandDeliveryState

        if turnOffRequested {
            deliveryState = try await performSandboxAwareBackgroundTask(
                description: "Turning off climate in \(resolved.name)"
            ) {
                try await service.runControl(
                    action: "auto_conditioning_stop",
                    vin: resolved.vin,
                    humanName: "stopping climate",
                    allowAsyncWake: true
                )
            }
            startedAt = nil
            target = nil
            summary = deliveryState == .wakingVehicle
                ? "Waking \(resolved.name) to turn off climate."
                : "Climate is off."
        } else if let targetF {
            let runningAnchor: Date?
            if let cardInteractionID, previous?.interactionID == cardInteractionID,
               previous?.recentlyStarted(observation: observation) == true {
                runningAnchor = previous?.startedAt
            } else {
                runningAnchor = await service.climateRunningAnchor(vin: resolved.vin)
            }
            let shouldStartClimate = runningAnchor == nil
            let celsius = SetCabinTemperatureIntent.targetCelsius(
                for: Measurement(value: targetF, unit: .fahrenheit)
            )
            try await performSandboxAwareBackgroundTask(
                description: "Updating cabin temperature in \(resolved.name)"
            ) {
                if shouldStartClimate {
                    try await service.runControl(
                        action: "auto_conditioning_start",
                        vin: resolved.vin,
                        humanName: "starting climate"
                    )
                }
                guard scope == service.sessionScopeID else { throw FleetKitError.sessionExpired }
                try await service.runControl(
                    action: "set_temps",
                    vin: resolved.vin,
                    params: ["driver_temp": .double(celsius), "passenger_temp": .double(celsius)],
                    humanName: "setting the cabin temperature"
                )
            }
            startedAt = shouldStartClimate ? .now : runningAnchor
            target = celsius
            deliveryState = .confirmed
            summary = "Cabin target updated."
        } else {
            deliveryState = try await performSandboxAwareBackgroundTask(
                description: "Starting climate in \(resolved.name)"
            ) {
                try await service.runControl(
                    action: "auto_conditioning_start",
                    vin: resolved.vin,
                    humanName: "starting climate",
                    allowAsyncWake: true
                )
            }
            startedAt = deliveryState == .confirmed ? .now : nil
            target = nil
            summary = deliveryState == .wakingVehicle
                ? "Waking \(resolved.name) to start climate."
                : "Climate is on."
        }
        guard scope == service.sessionScopeID else { throw FleetKitError.sessionExpired }
        ClimateCommandReceipt(
            sessionScope: scope,
            interactionID: cardInteractionID ?? UUID().uuidString,
            date: .now,
            targetCelsius: target ?? previous?.targetCelsius,
            targetSetAt: target == nil ? previous?.targetSetAt : .now,
            running: !turnOffRequested,
            startedAt: startedAt,
            summary: summary,
            deliveryState: deliveryState
        ).save(vin: resolved.vin, group: service.appGroupIdentifier)
        SiriSnippetStateStore.shared.notifyChanged(.vehicleStatus(vin: resolved.vin))
        // App Intents re-performs the originating climate snippet after the tap.
        GetVehicleStatusIntent.reload()
        return .result()
    }
}
