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
        case .warmUp: String(localized: "Warm up my car", comment: "Siri voice shortcut phrase to heat the car cabin")
        case .coolDown: String(localized: "Cool down my car", comment: "Siri voice shortcut phrase to cool the car cabin")
        case .lock: String(localized: "Lock my car", comment: "Siri voice shortcut phrase to lock the car")
        case .checkStatus: String(localized: "Check my car", comment: "Siri voice shortcut phrase to check car status")
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
        attributes.contentDescription = String(
            localized: "\(phrase) without needing to say the app name.",
            comment: "Spotlight description for a personal Siri voice shortcut phrase"
        )
        attributes.keywords = [
            phrase,
            String(localized: "my car", comment: "Spotlight search keyword for vehicle voice shortcuts"),
            String(localized: "car", comment: "Spotlight search keyword for vehicle voice shortcuts"),
            String(localized: "climate", comment: "Spotlight search keyword for climate voice shortcuts"),
            String(localized: "warm up", comment: "Spotlight search keyword for warming up the car"),
            String(localized: "cool down", comment: "Spotlight search keyword for cooling down the car"),
            String(localized: "lock", comment: "Spotlight search keyword for locking the car"),
            "my car", "car", "climate", "warm up", "cool down", "lock"
        ]
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
            vin.isEmpty ? nil : VehicleEntity(id: vin, name: String(localized: "Car", comment: "Fallback vehicle name when performing a voice shortcut"))
        }

        switch self {
        case .warmUp, .coolDown:
            let intent = StartClimateIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            return (
                result.value?.vin,
                result.value?.summary ?? String(localized: "Climate is starting in your car.", comment: "Fallback confirmation after starting climate from a voice shortcut")
            )
        case .lock:
            let intent = LockVehicleIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            return (
                result.value?.vin,
                result.value?.summary ?? String(localized: "Locked your car.", comment: "Fallback confirmation after locking the car from a voice shortcut")
            )
        case .checkStatus:
            let intent = GetVehicleStatusIntent()
            intent.vehicle = targetEntity
            let result = try await intent.perform()
            if let status = result.value {
                return (status.vin, "\(status.vehicleName): \(status.statusSummary)")
            }
            return (nil, String(localized: "Refreshed your car's status.", comment: "Fallback confirmation after checking vehicle status from a voice shortcut"))
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
        // Clear any legacy auto-suggested NSUserActivity shortcuts so they don't compete
        // with iOS 27.3 Siri AI `@AppIntent(.tool)` routing. Users can still manually pin
        // 1-tap voice phrases via `AppIntentDiscoveryCard`.
        INVoiceShortcutCenter.shared.setShortcutSuggestions([])

        guard let vehicleEntity = VehicleEntity(vehicle: vehicle) else { return }

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
        case .charge(shouldStart: true):
            let intent = StartChargingIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard start charging")
        case .charge(shouldStart: false):
            let intent = StopChargingIntent()
            intent.vehicle = vehicleEntity
            await donate(intent, label: "dashboard stop charging")
        case .setChargeLimit(let percent):
            let intent = SetChargeLimitIntent()
            intent.vehicle = vehicleEntity
            intent.percent = percent
            await donate(intent, label: "dashboard set charge limit")
        case .setCabinTemperature(let celsius):
            let intent = SetCabinTemperatureIntent()
            intent.vehicle = vehicleEntity
            intent.temperature = Measurement(value: celsius, unit: .celsius)
            await donate(intent, label: "dashboard set cabin temperature")
        case .sentryMode(let shouldTurnOn):
            let intent = SetSentryModeIntent()
            intent.vehicle = vehicleEntity
            intent.on = shouldTurnOn
            await donate(intent, label: "dashboard sentry mode")
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

