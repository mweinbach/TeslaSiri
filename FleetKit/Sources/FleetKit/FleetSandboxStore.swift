import Foundation

/// Controls whether TeslaSiri and its Siri App Intents extension talk to the live
/// Tessie API, intercept write commands only (Dry-Run), or run against a self-contained
/// simulated Tesla (Demo Car).
public enum FleetSandboxMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case live
    case dryRun
    case demoVehicle

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .live: "Live"
        case .dryRun: "Dry-Run"
        case .demoVehicle: "Demo Car"
        }
    }

    public var explanation: String {
        switch self {
        case .live:
            "Reads and controls your real Tesla through your selected provider."
        case .dryRun:
            "Reads your real car's live status, but intercepts and logs every Siri and app command without touching your car."
        case .demoVehicle:
            "Simulates a Model Y for both the app and Siri—no provider sign-in needed. Commands update the demo car locally."
        }
    }

    public var interceptsWrites: Bool {
        self != .live
    }
}

/// Built-in vehicle scenarios for testing Siri's conditional logic (freezing cabin prep,
/// hot cabin cool-down, overnight security checks, and low-battery trip readiness).
public enum FleetDemoPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case mildCommute
    case freezingMorning
    case hotCabin
    case roadTripPrep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mildCommute: "Mild Morning"
        case .freezingMorning: "Freezing Morning"
        case .hotCabin: "Hot Summer Cabin"
        case .roadTripPrep: "Trip Prep (Low Battery)"
        }
    }

    public var subtitle: String {
        switch self {
        case .mildCommute:
            "66°F inside · 58°F outside · 78% battery · Update ready"
        case .freezingMorning:
            "26°F inside · 22°F outside · Plugged in · Low FR tire (36.5 PSI)"
        case .hotCabin:
            "104°F inside · 93°F outside · Unlocked · Driver window vented"
        case .roadTripPrep:
            "42% battery (132 mi) · Plugged in at 80% limit · 70°F inside"
        }
    }

    public var systemImage: String {
        switch self {
        case .mildCommute: "sun.and.horizon"
        case .freezingMorning: "snowflake"
        case .hotCabin: "sun.max.fill"
        case .roadTripPrep: "bolt.car.fill"
        }
    }
}

/// An intercepted command recorded while Dry-Run or Demo Car mode is active.
public struct FleetSimulatedCommandEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var source: String
    public var mode: FleetSandboxMode
    public var vin: String
    public var vehicleName: String
    public var action: String
    public var parametersSummary: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        source: String,
        mode: FleetSandboxMode,
        vin: String,
        vehicleName: String,
        action: String,
        parametersSummary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.mode = mode
        self.vin = vin
        self.vehicleName = vehicleName
        self.action = action
        self.parametersSummary = parametersSummary
    }

    public var humanizedAction: String {
        switch action {
        case "door_lock": "Lock Doors"
        case "door_unlock": "Unlock Doors"
        case "auto_conditioning_start": "Start Climate"
        case "auto_conditioning_stop": "Stop Climate"
        case "set_temps": "Set Cabin Temperature"
        case "remote_defrost": "Set Max Defrost"
        case "set_seat_heat": "Set Seat Heater"
        case "set_seat_cool": "Set Seat Cooling"
        case "steering_wheel_heater": "Set Steering Wheel Heater"
        case "set_pet_mode": "Set Dog Mode"
        case "set_bioweapon_mode": "Set Bioweapon Defense"
        case "window_control": "Window Control"
        case "actuate_trunk": "Actuate Trunk / Frunk"
        case "charge_port_door_open": "Open Charge Port"
        case "charge_port_door_close": "Close Charge Port"
        case "charge_start": "Start Charging"
        case "charge_stop": "Stop Charging"
        case "set_charge_limit": "Set Charge Limit"
        case "set_charging_amps": "Set Charging Amps"
        case "set_sentry_mode": "Set Sentry Mode"
        case "flash_lights": "Flash Lights"
        case "honk_horn": "Honk Horn"
        case "navigation_request": "Send Navigation Destination"
        case "software_install": "Install Software Update"
        case "software_cancel": "Cancel Software Update"
        default: action
        }
    }
}

/// Mutable state of the simulated Tesla vehicle persisted in the shared App Group so
/// Siri App Intents and the main app read and mutate the same demo car.
public struct FleetDemoVehicleState: Codable, Equatable, Sendable {
    public static let demoVIN = "7SAYGDEE9SF000420"

    public var vin: String
    public var displayName: String
    public var carType: String
    public var exteriorColor: String
    public var preset: FleetDemoPreset

    public var batteryLevel: Double
    public var batteryRangeMiles: Double
    public var chargeLimitSOC: Double
    public var chargingState: String
    public var chargerPowerKW: Double
    public var chargeRateMPH: Double
    public var timeToFullCharge: Double
    public var chargingAmps: Int
    public var chargePortDoorOpen: Bool

    public var locked: Bool
    public var sentryModeOn: Bool

    public var insideTempF: Double
    public var outsideTempF: Double
    public var targetTempF: Double
    public var hvacOn: Bool
    public var defrostOn: Bool
    public var petModeOn: Bool
    public var bioweaponModeOn: Bool
    public var steeringWheelHeaterOn: Bool
    public var seatHeaterLevels: [String: Int]

    public var frontDriverWindowOpen: Bool
    public var frontPassengerWindowOpen: Bool
    public var rearDriverWindowOpen: Bool
    public var rearPassengerWindowOpen: Bool
    public var frontTrunkOpen: Bool
    public var rearTrunkOpen: Bool

    public var frontLeftPSI: Double
    public var frontRightPSI: Double
    public var rearLeftPSI: Double
    public var rearRightPSI: Double

    public var latitude: Double
    public var longitude: Double
    public var odometerMiles: Double

    public var currentSoftwareVersion: String
    public var availableSoftwareVersion: String?
    public var softwareStatus: String?
    public var lastNavigationDestination: String?
    public var updatedAtMS: Int64

    public static func make(preset: FleetDemoPreset, now: Date = .now) -> FleetDemoVehicleState {
        let nowMS = Int64(now.timeIntervalSince1970 * 1_000)
        var base = FleetDemoVehicleState(
            vin: demoVIN,
            displayName: "Demo Model Y",
            carType: "modely",
            exteriorColor: "UltraRed",
            preset: preset,
            batteryLevel: 78,
            batteryRangeMiles: 248,
            chargeLimitSOC: 80,
            chargingState: "Disconnected",
            chargerPowerKW: 0,
            chargeRateMPH: 0,
            timeToFullCharge: 0,
            chargingAmps: 48,
            chargePortDoorOpen: false,
            locked: true,
            sentryModeOn: true,
            insideTempF: 66,
            outsideTempF: 58,
            targetTempF: 70,
            hvacOn: false,
            defrostOn: false,
            petModeOn: false,
            bioweaponModeOn: false,
            steeringWheelHeaterOn: false,
            seatHeaterLevels: [:],
            frontDriverWindowOpen: false,
            frontPassengerWindowOpen: false,
            rearDriverWindowOpen: false,
            rearPassengerWindowOpen: false,
            frontTrunkOpen: false,
            rearTrunkOpen: false,
            frontLeftPSI: 42.1,
            frontRightPSI: 42.0,
            rearLeftPSI: 41.9,
            rearRightPSI: 42.2,
            latitude: 37.3349,
            longitude: -122.0090,
            odometerMiles: 14_820.4,
            currentSoftwareVersion: "2026.32.4",
            availableSoftwareVersion: "2026.38.1",
            softwareStatus: "available",
            lastNavigationDestination: nil,
            updatedAtMS: nowMS
        )

        switch preset {
        case .mildCommute:
            break
        case .freezingMorning:
            base.batteryLevel = 62
            base.batteryRangeMiles = 196
            base.chargingState = "Stopped"
            base.chargePortDoorOpen = true
            base.insideTempF = 26
            base.outsideTempF = 22
            base.targetTempF = 68
            base.frontRightPSI = 36.5
        case .hotCabin:
            base.batteryLevel = 84
            base.batteryRangeMiles = 268
            base.locked = false
            base.sentryModeOn = false
            base.insideTempF = 104
            base.outsideTempF = 93
            base.targetTempF = 72
            base.frontDriverWindowOpen = true
        case .roadTripPrep:
            base.batteryLevel = 42
            base.batteryRangeMiles = 132
            base.chargeLimitSOC = 80
            base.chargingState = "Stopped"
            base.chargePortDoorOpen = true
            base.insideTempF = 70
            base.outsideTempF = 64
        }

        return base
    }

    public mutating func applyControl(action: String, params: [String: FleetControlValue], now: Date = .now) {
        updatedAtMS = Int64(now.timeIntervalSince1970 * 1_000)

        switch action {
        case "door_lock":
            locked = true
        case "door_unlock":
            locked = false
        case "auto_conditioning_start":
            hvacOn = true
        case "auto_conditioning_stop":
            hvacOn = false
            defrostOn = false
            petModeOn = false
            bioweaponModeOn = false
            steeringWheelHeaterOn = false
            seatHeaterLevels = [:]
        case "set_temps":
            if let celsius = params["driver_temp"]?.numericValue ?? params["passenger_temp"]?.numericValue {
                let fahrenheit = (celsius * 9.0 / 5.0) + 32.0
                targetTempF = (fahrenheit * 10).rounded() / 10
            }
        case "remote_defrost":
            let on = params["on"]?.booleanValue ?? true
            defrostOn = on
            if on {
                hvacOn = true
                targetTempF = 82.0
            }
        case "set_seat_heat", "set_seat_cool":
            let level = params["level"]?.intValue ?? 0
            let seatKey = Self.seatDisplayName(for: params["seat"]?.stringValue ?? "front_left")
            if level <= 0 {
                seatHeaterLevels.removeValue(forKey: seatKey)
            } else {
                seatHeaterLevels[seatKey] = min(level, 3)
                hvacOn = true
            }
        case "steering_wheel_heater":
            let on = params["on"]?.booleanValue ?? true
            steeringWheelHeaterOn = on
            if on { hvacOn = true }
        case "set_pet_mode":
            let on = params["on"]?.booleanValue ?? true
            petModeOn = on
            if on { hvacOn = true }
        case "set_bioweapon_mode":
            let on = params["on"]?.booleanValue ?? true
            bioweaponModeOn = on
            if on { hvacOn = true }
        case "window_control":
            let isVent = params["command"]?.stringValue == "vent"
            frontDriverWindowOpen = isVent
            frontPassengerWindowOpen = isVent
            rearDriverWindowOpen = isVent
            rearPassengerWindowOpen = isVent
        case "actuate_trunk":
            if params["which_trunk"]?.stringValue == "front" {
                frontTrunkOpen = true
            } else {
                rearTrunkOpen.toggle()
            }
        case "charge_port_door_open":
            chargePortDoorOpen = true
        case "charge_port_door_close":
            if chargingState != "Charging" {
                chargePortDoorOpen = false
            }
        case "charge_start":
            chargePortDoorOpen = true
            chargingState = "Charging"
            chargerPowerKW = 11.5
            chargeRateMPH = 44
            let neededSOC = max(chargeLimitSOC - batteryLevel, 5)
            timeToFullCharge = max((neededSOC * 0.78) / 11.5, 0.25)
        case "charge_stop":
            chargingState = "Stopped"
            chargerPowerKW = 0
            chargeRateMPH = 0
            timeToFullCharge = 0
        case "set_charge_limit":
            if let percent = params["percent"]?.numericValue {
                chargeLimitSOC = min(max(percent.rounded(), 50), 100)
            }
        case "set_charging_amps":
            if let amps = params["amps"]?.intValue {
                chargingAmps = min(max(amps, 5), 48)
            }
        case "set_sentry_mode":
            sentryModeOn = params["on"]?.booleanValue ?? true
        case "navigation_request":
            lastNavigationDestination = params["value"]?.stringValue
        default:
            break
        }
    }

    public mutating func applySoftwareInstall(offsetSec: Int, now: Date = .now) {
        updatedAtMS = Int64(now.timeIntervalSince1970 * 1_000)
        softwareStatus = offsetSec > 0 ? "scheduled" : "installing"
    }

    public mutating func applySoftwareCancel(now: Date = .now) {
        updatedAtMS = Int64(now.timeIntervalSince1970 * 1_000)
        if availableSoftwareVersion != nil {
            softwareStatus = "available"
        }
    }

    public var openClosureNames: [String] {
        var names: [String] = []
        if frontTrunkOpen { names.append("Frunk") }
        if rearTrunkOpen { names.append("Trunk") }
        if frontDriverWindowOpen { names.append("Driver window") }
        if frontPassengerWindowOpen { names.append("Passenger window") }
        if rearDriverWindowOpen { names.append("Rear left window") }
        if rearPassengerWindowOpen { names.append("Rear right window") }
        return names
    }

    public var vehicleInfo: FleetVehicleInfo {
        FleetVehicleInfo(
            vin: vin,
            displayName: displayName,
            vehicleTag: "demo",
            carType: carType,
            exteriorColor: exteriorColor
        )
    }

    public var snapshotInfo: FleetSnapshotInfo {
        let closures = openClosureNames
        return FleetSnapshotInfo(
            vin: vin,
            batteryLevel: batteryLevel,
            batteryRangeMiles: batteryRangeMiles,
            chargeLimitSOC: chargeLimitSOC,
            chargingState: chargingState,
            chargerPowerKW: chargerPowerKW > 0 ? chargerPowerKW : nil,
            chargePortDoorOpen: chargePortDoorOpen,
            locked: locked,
            sentryModeOn: sentryModeOn,
            chargeRateMPH: chargeRateMPH > 0 ? chargeRateMPH : nil,
            timeToFullCharge: timeToFullCharge > 0 ? timeToFullCharge : nil,
            insideTemp: insideTempF,
            outsideTemp: outsideTempF,
            targetTemp: targetTempF,
            hvacOn: hvacOn,
            latitude: latitude,
            longitude: longitude,
            odometer: odometerMiles,
            speed: 0,
            updatedAt: updatedAtMS,
            climateKeeperMode: petModeOn ? "dog" : "off",
            defrostMode: defrostOn ? "2" : "0",
            tires: FleetTirePressuresInfo(
                frontLeftPSI: frontLeftPSI,
                frontRightPSI: frontRightPSI,
                rearLeftPSI: rearLeftPSI,
                rearRightPSI: rearRightPSI,
                hardWarnings: 0,
                softWarnings: [frontLeftPSI, frontRightPSI, rearLeftPSI, rearRightPSI].filter { $0 < 38.0 }.count,
                lastMeasuredAt: updatedAtMS
            ),
            temperatureInFahrenheit: true,
            shiftState: "P",
            openClosures: closures.isEmpty ? nil : closures,
            seatHeaterLevels: seatHeaterLevels.isEmpty ? nil : seatHeaterLevels,
            steeringWheelHeaterOn: steeringWheelHeaterOn
        )
    }

    public var softwareInfo: FleetSoftwareInfo {
        let hasUpdate = availableSoftwareVersion != nil
        let isInstallable = hasUpdate && (softwareStatus == "available" || softwareStatus == "scheduled")
        return FleetSoftwareInfo(
            currentVersion: currentSoftwareVersion,
            availableVersion: availableSoftwareVersion,
            updateAvailable: hasUpdate,
            installable: isInstallable,
            status: softwareStatus,
            downloadPercent: hasUpdate ? 100 : nil,
            installPercent: softwareStatus == "installing" ? 15 : 0,
            expectedDurationMinutes: hasUpdate ? 25 : nil,
            releaseNotes: Self.demoReleaseNotes(version: availableSoftwareVersion ?? currentSoftwareVersion)
        )
    }

    public static func demoReleaseNotes(version: String) -> [FleetReleaseNoteInfo] {
        [
            FleetReleaseNoteInfo(
                title: "Siri Cabin Preconditioning",
                subtitle: "Climate & Comfort",
                details: "Faster cabin warm-up and cool-down coordination with automatic seat and steering wheel comfort controls.",
                customerVersion: version
            ),
            FleetReleaseNoteInfo(
                title: "Full Self-Driving (Supervised)",
                subtitle: "v14.4",
                details: "Smoother unprotected turns, earlier lane selection on highway interchanges, and improved parking lot navigation.",
                customerVersion: version
            ),
            FleetReleaseNoteInfo(
                title: "Adaptive High Beams",
                subtitle: "Vision",
                details: "Selectively dims individual headlight pixels around oncoming traffic and cyclists.",
                customerVersion: version
            )
        ]
    }

    public static func demoDrives(vin: String, now: Date = .now) -> [FleetDriveInfo] {
        let nowMS = Int64(now.timeIntervalSince1970 * 1_000)
        return [
            FleetDriveInfo(
                sessionID: "\(vin):demo-102",
                vin: vin,
                distanceMiles: 14.6,
                durationMS: 1_560_000,
                avgSpeedMPH: 33.7,
                maxSpeedMPH: 64.0,
                energyUsedKWH: 3.6,
                startedAt: nowMS - 14_400_000,
                endedAt: nowMS - 12_840_000,
                startAddress: "1 Apple Park Way, Cupertino, CA",
                endAddress: "Palo Alto Caltrain, Palo Alto, CA",
                startLatitude: 37.3349,
                startLongitude: -122.0090,
                endLatitude: 37.4430,
                endLongitude: -122.1650,
                startingBatteryPercent: 83,
                endingBatteryPercent: 78,
                ratedRangeUsedMiles: 15.2,
                autopilotDistanceMiles: 11.4,
                insideTempF: 69.5,
                outsideTempF: 61.0,
                tag: "Commute"
            ),
            FleetDriveInfo(
                sessionID: "\(vin):demo-101",
                vin: vin,
                distanceMiles: 36.2,
                durationMS: 2_640_000,
                avgSpeedMPH: 49.4,
                maxSpeedMPH: 71.0,
                energyUsedKWH: 9.2,
                startedAt: nowMS - 98_000_000,
                endedAt: nowMS - 95_360_000,
                startAddress: "Palo Alto, CA",
                endAddress: "San Francisco International Airport, CA",
                startLatitude: 37.4430,
                startLongitude: -122.1650,
                endLatitude: 37.6213,
                endLongitude: -122.3790,
                startingBatteryPercent: 90,
                endingBatteryPercent: 77,
                ratedRangeUsedMiles: 38.0,
                autopilotDistanceMiles: 31.8,
                insideTempF: 70.0,
                outsideTempF: 57.0,
                tag: "Personal"
            )
        ]
    }

    public static func demoDrivePath(driveID: String?, from: Date, to: Date) -> [FleetDriveRoutePoint] {
        let startMS = Int64(from.timeIntervalSince1970 * 1_000)
        let isAirportTrip = driveID?.contains("demo-101") == true
        let waypoints: [(lat: Double, lon: Double, speed: Double, ap: String)] = isAirportTrip
            ? [
                (37.4430, -122.1650, 0, "Standby"),
                (37.4545, -122.1502, 34, "Off"),
                (37.4698, -122.1422, 62, "Autosteer"),
                (37.4982, -122.1778, 66, "Autosteer"),
                (37.5305, -122.2286, 68, "Autosteer"),
                (37.5582, -122.2755, 65, "Autosteer"),
                (37.5844, -122.3268, 60, "Autosteer"),
                (37.6065, -122.3642, 42, "Autosteer"),
                (37.6213, -122.3790, 0, "Off")
            ]
            : [
                (37.3349, -122.0090, 0, "Standby"),
                (37.3368, -122.0185, 28, "Off"),
                (37.3412, -122.0365, 58, "Autosteer"),
                (37.3548, -122.0672, 64, "Autosteer"),
                (37.3726, -122.0984, 63, "Autosteer"),
                (37.3945, -122.1292, 60, "Autosteer"),
                (37.4128, -122.1476, 44, "Autosteer"),
                (37.4295, -122.1548, 30, "Off"),
                (37.4430, -122.1650, 0, "Off")
            ]

        return waypoints.enumerated().map { index, wp in
            FleetDriveRoutePoint(
                latitude: wp.lat,
                longitude: wp.lon,
                speedMPH: wp.speed,
                autopilotState: wp.ap,
                timestampMS: startMS + Int64(index) * 180_000
            )
        }
    }

    public static func demoCharges(vin: String, now: Date = .now) -> [FleetChargeInfo] {
        let nowMS = Int64(now.timeIntervalSince1970 * 1_000)
        return [
            FleetChargeInfo(
                sessionID: "\(vin):demo-charge-2",
                vin: vin,
                startedAt: nowMS - 43_200_000,
                endedAt: nowMS - 32_400_000,
                location: "Home Wall Connector",
                latitude: 37.3349,
                longitude: -122.0090,
                isSupercharger: false,
                odometerMiles: 14_805.8,
                energyAddedKWH: 24.5,
                energyUsedKWH: 26.2,
                milesAdded: 98.0,
                startingBatteryPercent: 52,
                endingBatteryPercent: 83,
                cost: 6.30
            ),
            FleetChargeInfo(
                sessionID: "\(vin):demo-charge-1",
                vin: vin,
                startedAt: nowMS - 172_800_000,
                endedAt: nowMS - 170_700_000,
                location: "San Mateo Supercharger",
                latitude: 37.5541,
                longitude: -122.2974,
                isSupercharger: true,
                odometerMiles: 14_690.0,
                energyAddedKWH: 46.8,
                energyUsedKWH: 50.4,
                milesAdded: 186.0,
                startingBatteryPercent: 18,
                endingBatteryPercent: 80,
                cost: 19.65
            )
        ]
    }

    public static func demoBatteryHealth(vin: String, odometerMiles: Double) -> FleetBatteryHealthInfo {
        FleetBatteryHealthInfo(
            vin: vin,
            healthPercent: 97.4,
            degradationPercent: 2.6,
            usableCapacityKWH: 76.9,
            originalCapacityKWH: 79.0,
            maxRangeMiles: 318.0,
            maxIdealRangeMiles: 326.0,
            odometerMiles: odometerMiles,
            energyRemainingKWH: 60.0,
            lifetimeEnergyUsedKWH: 4_120.5,
            phantomDrainPercent: 0.4,
            packVoltage: 392.1,
            packCurrentAmps: -0.6,
            moduleTempMinF: 68.0,
            moduleTempMaxF: 71.6
        )
    }

    public static func demoConsumption(now: Date = .now) -> FleetConsumptionInfo {
        let nowMS = Int64(now.timeIntervalSince1970 * 1_000)
        return FleetConsumptionInfo(
            lastChargeAt: nowMS - 32_400_000,
            distanceDrivenMiles: 14.6,
            batteryPercentUsed: 5.0,
            batteryPercentUsedByDriving: 4.5,
            ratedRangeUsedMiles: 16.5,
            ratedRangeUsedByDrivingMiles: 15.2,
            energyUsedKWH: 4.0,
            energyUsedByDrivingKWH: 3.6
        )
    }

    public static let supportedControlActions = FleetControlActionsInfo(
        actions: [
            "door_lock",
            "door_unlock",
            "auto_conditioning_start",
            "auto_conditioning_stop",
            "set_temps",
            "remote_defrost",
            "set_pet_mode",
            "set_bioweapon_mode",
            "set_seat_heat",
            "set_seat_cool",
            "steering_wheel_heater",
            "window_control",
            "actuate_trunk",
            "flash_lights",
            "honk_horn",
            "navigation_request",
            "set_sentry_mode",
            "charge_port_door_open",
            "charge_port_door_close"
        ],
        chargeActions: [
            "charge_start",
            "charge_stop",
            "set_charge_limit",
            "set_charging_amps"
        ],
        schemas: [:]
    )

    private static func seatDisplayName(for tessieSeat: String) -> String {
        switch tessieSeat {
        case "front_left": "Driver"
        case "front_right": "Passenger"
        case "rear_left": "Rear left"
        case "rear_center": "Rear center"
        case "rear_right": "Rear right"
        default: tessieSeat
        }
    }
}

/// Shared App Group persistence for Sandbox Mode, Demo Car state, and intercepted commands.
public struct FleetSandboxStore: Sendable {
    public static let shared = FleetSandboxStore()
    public static let maxCommandLogEntries = 40

    let appGroup: String
    private static let modeGenerationKey = "FleetKit.sandboxModeGeneration"

    public init(appGroup: String = FleetKitConfig.appGroupIdentifier) {
        self.appGroup = appGroup
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public func mode() -> FleetSandboxMode {
        guard let raw = defaults?.string(forKey: FleetKitConfig.sandboxModeDefaultsKey),
              let parsed = FleetSandboxMode(rawValue: raw) else {
            return .live
        }
        return parsed
    }

    public var sessionScope: String {
        let generation = defaults?.string(forKey: Self.modeGenerationKey) ?? "initial"
        return "\(appGroup).\(mode().rawValue).\(generation)"
    }

    public func setMode(_ mode: FleetSandboxMode) {
        if self.mode() != mode {
            defaults?.set(UUID().uuidString, forKey: Self.modeGenerationKey)
        }
        defaults?.set(mode.rawValue, forKey: FleetKitConfig.sandboxModeDefaultsKey)
        if mode == .demoVehicle, loadStoredDemoState() == nil {
            let preset = selectedPreset()
            saveDemoState(.make(preset: preset))
        }
    }

    public func selectedPreset() -> FleetDemoPreset {
        guard let raw = defaults?.string(forKey: FleetKitConfig.sandboxPresetDefaultsKey),
              let parsed = FleetDemoPreset(rawValue: raw) else {
            return .mildCommute
        }
        return parsed
    }

    @discardableResult
    public func applyPreset(_ preset: FleetDemoPreset, now: Date = .now) -> FleetDemoVehicleState {
        defaults?.set(preset.rawValue, forKey: FleetKitConfig.sandboxPresetDefaultsKey)
        let state = FleetDemoVehicleState.make(preset: preset, now: now)
        saveDemoState(state)
        return state
    }

    public func demoState() -> FleetDemoVehicleState {
        if let existing = loadStoredDemoState() {
            return existing
        }
        let fresh = FleetDemoVehicleState.make(preset: selectedPreset())
        saveDemoState(fresh)
        return fresh
    }

    public func saveDemoState(_ state: FleetDemoVehicleState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: FleetKitConfig.sandboxDemoStateDefaultsKey)
    }

    private func loadStoredDemoState() -> FleetDemoVehicleState? {
        guard let data = defaults?.data(forKey: FleetKitConfig.sandboxDemoStateDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FleetDemoVehicleState.self, from: data)
    }

    public func commandLog() -> [FleetSimulatedCommandEntry] {
        guard let data = defaults?.data(forKey: FleetKitConfig.sandboxCommandLogDefaultsKey),
              let entries = try? JSONDecoder().decode([FleetSimulatedCommandEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public func clearCommandLog() {
        defaults?.removeObject(forKey: FleetKitConfig.sandboxCommandLogDefaultsKey)
    }

    @discardableResult
    public func recordSimulatedControl(
        action: String,
        vin: String,
        vehicleName: String,
        params: [String: FleetControlValue] = [:],
        source: String,
        now: Date = .now
    ) -> FleetSimulatedCommandEntry {
        let currentMode = mode()
        if currentMode == .demoVehicle {
            var state = demoState()
            state.applyControl(action: action, params: params, now: now)
            saveDemoState(state)
        }

        let summary = Self.formatParameters(params)
        let entry = FleetSimulatedCommandEntry(
            timestamp: now,
            source: source,
            mode: currentMode == .live ? .dryRun : currentMode,
            vin: vin,
            vehicleName: vehicleName,
            action: action,
            parametersSummary: summary
        )
        appendLogEntry(entry)
        return entry
    }

    @discardableResult
    public func recordSimulatedSoftwareAction(
        isInstall: Bool,
        vin: String,
        vehicleName: String,
        offsetSec: Int = 0,
        source: String,
        now: Date = .now
    ) -> FleetSimulatedCommandEntry {
        let currentMode = mode()
        if currentMode == .demoVehicle {
            var state = demoState()
            if isInstall {
                state.applySoftwareInstall(offsetSec: offsetSec, now: now)
            } else {
                state.applySoftwareCancel(now: now)
            }
            saveDemoState(state)
        }

        let entry = FleetSimulatedCommandEntry(
            timestamp: now,
            source: source,
            mode: currentMode == .live ? .dryRun : currentMode,
            vin: vin,
            vehicleName: vehicleName,
            action: isInstall ? "software_install" : "software_cancel",
            parametersSummary: isInstall && offsetSec > 0 ? "offset_sec=\(offsetSec)" : nil
        )
        appendLogEntry(entry)
        return entry
    }

    private func appendLogEntry(_ entry: FleetSimulatedCommandEntry) {
        var entries = commandLog()
        entries.insert(entry, at: 0)
        if entries.count > Self.maxCommandLogEntries {
            entries = Array(entries.prefix(Self.maxCommandLogEntries))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults?.set(data, forKey: FleetKitConfig.sandboxCommandLogDefaultsKey)
    }

    public static func formatParameters(_ params: [String: FleetControlValue]) -> String? {
        guard !params.isEmpty else { return nil }
        return params.keys.sorted().map { key in
            "\(key)=\(params[key]?.displayString ?? "")"
        }.joined(separator: ", ")
    }
}

extension FleetControlValue {
    var displayString: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(format: "%.1f", value)
        case .bool(let value): value ? "true" : "false"
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        }
    }

    var numericValue: Double? {
        switch self {
        case .double(let value): value
        case .int(let value): Double(value)
        case .string(let value): Double(value)
        case .bool: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(value.rounded())
        case .string(let value): Int(value)
        case .bool: nil
        }
    }

    var booleanValue: Bool? {
        switch self {
        case .bool(let value): value
        case .string(let value): Bool(value)
        default: nil
        }
    }
}
