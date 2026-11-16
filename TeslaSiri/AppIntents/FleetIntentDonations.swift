import AppIntents
import CoreSpotlight
import FleetKit
import Intents
import OSLog

/// Natural app-nameless Siri phrases ("Warm up my car", "Cool down my car",
/// "Lock my car", "Check my car") backed by `NSUserActivity` + `INShortcut`
/// so users can also bind 1-tap Personal Siri Shortcuts without saying "Tesla"
/// or "TeslaSiri", alongside automatic Siri AI `@AppIntent(.tool)` discovery.
enum CarSiriVoicePhrase: String, CaseIterable, Identifiable {
    case warmUp = "com.maxweinbach.TeslaSiri.warmUpCar"
    case coolDown = "com.maxweinbach.TeslaSiri.coolDownCar"
    case lock = "com.maxweinbach.TeslaSiri.lockCar"
    case checkStatus = "com.maxweinbach.TeslaSiri.checkCar"

    var id: String { rawValue }

    var phrase: String {
        switch self {
        case .warmUp: "Warm up my car"
        case .coolDown: "Cool down my car"
        case .lock: "Lock my car"
        case .checkStatus: "Check my car"
        }
    }

    var systemImage: String {
        switch self {
        case .warmUp: "flame.fill"
        case .coolDown: "snowflake"
        case .lock: "lock.fill"
        case .checkStatus: "car.fill"
        }
    }

    func makeUserActivity(for vehicle: FleetVehicle?) -> NSUserActivity {
        let activity = NSUserActivity(activityType: rawValue)
        activity.title = phrase
        activity.suggestedInvocationPhrase = phrase
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(rawValue)

        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.contentDescription = "\(phrase) without needing to say the app name."
        attributes.keywords = [phrase, "my car", "car", "climate", "warm up", "cool down", "lock"]
        activity.contentAttributeSet = attributes

        if let vehicle, !vehicle.vin.isEmpty {
            activity.userInfo = ["vin": vehicle.vin]
            activity.requiredUserInfoKeys = ["vin"]
            activity.appEntityIdentifier = EntityIdentifier(for: VehicleEntity.self, identifier: vehicle.vin)
        }
        return activity
    }

    func makeShortcut(for vehicle: FleetVehicle?) -> INShortcut {
        INShortcut(userActivity: makeUserActivity(for: vehicle))
    }

    @MainActor
    func perform(vinOverride: String? = nil) async throws -> (vin: String?, summary: String) {
        let targetEntity: VehicleEntity? = vinOverride.flatMap { vin in
            vin.isEmpty ? nil : VehicleEntity(id: vin, name: "Car")
        }

        switch self {
        case .warmUp, .coolDown:
            let intent = StartClimateIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            return (result.value?.vin, result.value?.summary ?? "Climate is starting in your car.")
        case .lock:
            let intent = LockVehicleIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            return (result.value?.vin, result.value?.summary ?? "Locked your car.")
        case .checkStatus:
            let intent = GetVehicleStatusIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            if let status = result.value {
                return (status.vin, "\(status.vehicleName): \(status.statusSummary)")
            }
            return (nil, "Refreshed your car's status.")
        }
    }
}

/// App-side donations for actions completed from TeslaSiri's own UI, plus
/// proactive behavioral cues so Apple Intelligence routes natural "my car"
/// climate and status utterances without requiring "Tesla" in the prompt.
enum FleetIntentDonations {
    private static let logger = Logger(subsystem: FleetKitLog.subsystem, category: "AppIntents")

    static func clearVehicleSuggestions(for vehicles: [FleetVehicle]) async {
        INVoiceShortcutCenter.shared.setShortcutSuggestions([])
        let identifiers = vehicles.map { EntityIdentifier(for: VehicleEntity.self, identifier: $0.vin) }
        guard !identifiers.isEmpty else { return }
        do {
            try await IntentDonationManager.shared.deleteDonations(matching: .entityIdentifiers(identifiers))
        } catch {
            logger.warning("Could not clear vehicle donations: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func syncCarSuggestions(for vehicle: FleetVehicle?) async {
        let suggestions = CarSiriVoicePhrase.allCases.map { $0.makeShortcut(for: vehicle) }
        INVoiceShortcutCenter.shared.setShortcutSuggestions(suggestions)

        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        let revision = FleetSharedTokenStore.shared.sessionRevision
        let climateIntent = StartClimateIntent()
        climateIntent.vehicle = vehicleEntity
        await donate(climateIntent, label: "car climate capability cue")

        guard FleetSharedTokenStore.shared.sessionRevision == revision else { return }
        let statusIntent = GetVehicleStatusIntent()
        statusIntent.vehicle = vehicleEntity
        await donate(statusIntent, label: "car status capability cue")
    }

    static func donateControlCommand(_ command: VehicleControlCommand, for vehicle: FleetVehicle?) async {
        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        switch command {
        case .climate(shouldTurnOn: true):
            let intent = StartClimateIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard start climate")
        case .climate(shouldTurnOn: false):
            let intent = StopClimateIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard stop climate")
        case .defrost(let shouldTurnOn):
            let intent = SetMaxDefrostIntent()
            intent.vehicle = vehicleEntity
            intent.on = shouldTurnOn
            await donate(intent, label: "dashboard defrost")
        case .lock(shouldLock: true):
            let intent = LockVehicleIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard lock")
        case .lock(shouldLock: false):
            let intent = UnlockVehicleIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard unlock")
        case .ventWindows:
            let intent = VentWindowsIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard vent windows")
        case .rearTrunk(open: false):
            return
        case .openFrunk, .rearTrunk(open: true):
            let intent = OpenTrunkIntent()
            intent.vehicle = vehicleEntity
            intent.trunk = command == .openFrunk ? .front : .rear
            await donate(intent, label: "dashboard open trunk")
        case .chargePort(let open):
            let intent = SetChargePortIntent()
            intent.vehicle = vehicleEntity
            intent.action = open ? .open : .close
            await donate(intent, label: "dashboard charge port")
        case .petMode(let shouldTurnOn):
            let intent = SetPetModeIntent()
            intent.vehicle = vehicleEntity
            intent.on = shouldTurnOn
            await donate(intent, label: "dashboard pet mode")
        case .flashLights:
            let intent = FlashLightsIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard flash lights")
        case .honk:
            let intent = HonkHornIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard honk horn")
        }
    }

    static func donateManualStatusRefresh(for vehicle: FleetVehicle?) async {
        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        let intent = GetVehicleStatusIntent()
        intent.vehicle = vehicleEntity
        await donate(intent, label: "manual vehicle status refresh")
    }

    static func donateSoftwareStatusRefresh(for vehicle: FleetVehicle?) async {
        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        let intent = GetSoftwareStatusIntent()
        intent.vehicle = vehicleEntity
        await donate(intent, label: "software status refresh")
    }

    static func donateSoftwareInstall(for vehicle: FleetVehicle?) async {
        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        let intent = InstallSoftwareUpdateIntent()
        intent.vehicle = vehicleEntity
        await donate(intent, label: "software install")
    }

    static func donateSoftwareCancel(for vehicle: FleetVehicle?) async {
        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

        let intent = CancelSoftwareUpdateIntent()
        intent.vehicle = vehicleEntity
        await donate(intent, label: "software cancel")
    }

    private static func donate(_ intent: some AppIntent, label: String) async {
        do {
            let revision = FleetSharedTokenStore.shared.sessionRevision
            let id = try await intent.donate()
            guard FleetSharedTokenStore.shared.sessionRevision == revision else {
                try await IntentDonationManager.shared.deleteDonations(matching: .donationIdentifier(id))
                return
            }
            logger.info("Donated intent for \(label, privacy: .public)")
        } catch {
            logger.warning("Intent donation failed for \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension VehicleEntity {
    init?(vehicle: FleetVehicle?) {
        guard let vehicle, !vehicle.vin.isEmpty else { return nil }
        self.init(id: vehicle.vin, name: vehicle.name)
    }
}

