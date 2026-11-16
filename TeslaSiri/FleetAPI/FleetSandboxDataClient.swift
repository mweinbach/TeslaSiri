import FleetKit
import Foundation

/// Wraps the live `FleetAPIClient` so the app respects the shared `FleetSandboxStore`
/// mode (`Live`, `Dry-Run`, or `Demo Car`) in lockstep with Siri App Intents.
struct FleetSandboxDataClient: FleetDataLoading {
    let liveClient: any FleetDataLoading
    var sandbox: FleetSandboxStore = .shared

    // MARK: - Bootstrap & Sync

    func bootstrap() async throws -> FleetAPIPage<FleetBootstrap> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.bootstrap()
        }

        let state = sandbox.demoState()
        let vehicle = Self.makeVehicle(from: state)
        let bootstrap = FleetBootstrap(
            activeCharging: Self.makeChargingSessions(from: state),
            capabilities: Self.demoCapabilities,
            recentDrives: Self.makeDrives(vin: state.vin, includeRoute: false, nowMS: state.updatedAtMS),
            user: FleetUser(
                authType: "sandbox",
                email: "demo@teslasiri.local",
                id: "demo-user",
                name: "Demo Driver",
                role: "owner",
                scopes: ["vehicles:read", "vehicle_commands", "vehicle_history", "telemetry:read"],
                units: "imperial"
            ),
            vehicles: [vehicle]
        )
        return makePage(bootstrap, cursor: state.updatedAtMS, requestID: "demo-bootstrap")
    }

    func capabilities() async throws -> FleetAPIPage<FleetCapabilities> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.capabilities()
        }
        return makePage(Self.demoCapabilities, requestID: "demo-capabilities")
    }

    func changes(since cursor: Int64) async throws -> FleetAPIPage<FleetSyncChanges> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.changes(since: cursor)
        }
        let state = sandbox.demoState()
        let vehicle = Self.makeVehicle(from: state)
        let nextCursor = max(cursor + 1, state.updatedAtMS)
        return makePage(
            FleetSyncChanges(latest: vehicle.latest.map { [$0] } ?? [], vehicles: [vehicle]),
            cursor: nextCursor,
            requestID: "demo-sync"
        )
    }

    // MARK: - Live Snapshot & Vehicle Controls

    func latestSnapshot(vin: String, includingTires: Bool) async throws -> FleetAPIPage<FleetLatestSnapshot> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.latestSnapshot(vin: vin, includingTires: includingTires)
        }
        let state = sandbox.demoState()
        return makePage(Self.makeSnapshot(from: state), requestID: "demo-live")
    }

    func runControl(
        action: String,
        vin: String,
        params: [String: JSONValue]
    ) async throws -> FleetAPIPage<[String: JSONValue]> {
        let mode = sandbox.mode()
        guard mode.interceptsWrites else {
            return try await liveClient.runControl(action: action, vin: vin, params: params)
        }

        let controlParams = Self.convertParameters(params)
        let vehicleName = mode == .demoVehicle ? sandbox.demoState().displayName : FleetKitLog.vin(vin)
        sandbox.recordSimulatedControl(
            action: action,
            vin: vin,
            vehicleName: vehicleName,
            params: controlParams,
            source: "App"
        )
        return makePage(
            ["result": true, "simulated": true, "mode": .string(mode.rawValue)],
            requestID: "\(mode.rawValue)-\(action)"
        )
    }

    // MARK: - Drives, Routes & Charging

    func activeDrive(
        vin: String,
        includeRoute: Bool,
        routeMaxPoints: Int?
    ) async throws -> FleetAPIPage<FleetActiveDriveSession> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.activeDrive(vin: vin, includeRoute: includeRoute, routeMaxPoints: routeMaxPoints)
        }
        return makePage(FleetActiveDriveSession(active: false, vin: vin), requestID: "demo-active-drive")
    }

    func drives(vin: String, limit: Int?, includeRoute: Bool) async throws -> FleetAPIPage<[FleetDriveSession]> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.drives(vin: vin, limit: limit, includeRoute: includeRoute)
        }
        let state = sandbox.demoState()
        let sessions = Self.makeDrives(vin: vin, includeRoute: includeRoute, nowMS: state.updatedAtMS)
        let capped = limit.map { Array(sessions.prefix(max($0, 0))) } ?? sessions
        return makePage(capped, requestID: "demo-drives")
    }

    func driveRoute(
        sessionID: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?,
        maxPoints: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.driveRoute(
                sessionID: sessionID,
                startTime: startTime,
                endTime: endTime,
                limit: limit,
                maxPoints: maxPoints
            )
        }
        let baseStart = startTime ?? Int64(Date().timeIntervalSince1970 * 1_000) - 14_400_000
        return makePage(Self.makeDemoRoute(startMS: baseStart), requestID: "demo-route")
    }

    func chargingSessions(vin: String, limit: Int?) async throws -> FleetAPIPage<[FleetChargeSession]> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.chargingSessions(vin: vin, limit: limit)
        }
        let state = sandbox.demoState()
        let sessions = Self.makeChargingSessions(from: state)
        let capped = limit.map { Array(sessions.prefix(max($0, 0))) } ?? sessions
        return makePage(capped, requestID: "demo-charging")
    }

    // MARK: - Software Updates

    func softwareUpdate(
        vin: String,
        includeReleaseNotes: Bool,
        refresh: Bool
    ) async throws -> FleetAPIPage<FleetSoftwareUpdate> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.softwareUpdate(vin: vin, includeReleaseNotes: includeReleaseNotes, refresh: refresh)
        }
        let state = sandbox.demoState()
        return makePage(Self.makeSoftwareUpdate(from: state, includeReleaseNotes: includeReleaseNotes), requestID: "demo-software")
    }

    func installSoftwareUpdate(vin: String, offsetSec: Int) async throws -> FleetAPIPage<[String: JSONValue]> {
        let mode = sandbox.mode()
        guard mode.interceptsWrites else {
            return try await liveClient.installSoftwareUpdate(vin: vin, offsetSec: offsetSec)
        }
        let vehicleName = mode == .demoVehicle ? sandbox.demoState().displayName : FleetKitLog.vin(vin)
        sandbox.recordSimulatedSoftwareAction(
            isInstall: true,
            vin: vin,
            vehicleName: vehicleName,
            offsetSec: offsetSec,
            source: "App"
        )
        return makePage(["requested": true, "simulated": true], requestID: "\(mode.rawValue)-software-install")
    }

    func cancelSoftwareUpdate(vin: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        let mode = sandbox.mode()
        guard mode.interceptsWrites else {
            return try await liveClient.cancelSoftwareUpdate(vin: vin)
        }
        let vehicleName = mode == .demoVehicle ? sandbox.demoState().displayName : FleetKitLog.vin(vin)
        sandbox.recordSimulatedSoftwareAction(
            isInstall: false,
            vin: vin,
            vehicleName: vehicleName,
            source: "App"
        )
        return makePage(["canceled": true, "simulated": true], requestID: "\(mode.rawValue)-software-cancel")
    }

    // MARK: - Telemetry & Diagnostics Export

    func locations(
        vin: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.locations(vin: vin, startTime: startTime, endTime: endTime, limit: limit)
        }
        let state = sandbox.demoState()
        return makePage(Self.makeDemoRoute(startMS: state.updatedAtMS - 1_800_000), requestID: "demo-locations")
    }

    func telemetrySeries(
        vin: String,
        topic: String?,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?,
        maxPoints: Int?,
        fields: [String]
    ) async throws -> FleetAPIPage<[FleetTelemetrySeriesPoint]> {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.telemetrySeries(
                vin: vin,
                topic: topic,
                startTime: startTime,
                endTime: endTime,
                limit: limit,
                maxPoints: maxPoints,
                fields: fields
            )
        }
        let state = sandbox.demoState()
        let series: [FleetTelemetrySeriesPoint] = [
            [
                "timestamp": .integer(Int(state.updatedAtMS)),
                "speed": 0,
                "battery_level": .double(state.batteryLevel),
                "inside_temp": .double(state.insideTempF)
            ]
        ]
        return makePage(series, requestID: "demo-telemetry")
    }

    func rawVehicleDataExport(vin: String) async throws -> FleetRawDataExport {
        guard sandbox.mode() == .demoVehicle else {
            return try await liveClient.rawVehicleDataExport(vin: vin)
        }
        let state = sandbox.demoState()
        return FleetRawDataExport(
            apiBaseURL: "sandbox://demo-vehicle",
            appSchemaVersion: 2,
            generatedAt: state.updatedAtMS,
            responses: [
                FleetRawAPIResponse(
                    apiVersion: "sandbox-1.0",
                    body: .object([
                        "vin": .string(state.vin),
                        "display_name": .string(state.displayName),
                        "preset": .string(state.preset.rawValue),
                        "inside_temp_f": .double(state.insideTempF),
                        "outside_temp_f": .double(state.outsideTempF),
                        "target_temp_f": .double(state.targetTempF),
                        "hvac_on": .bool(state.hvacOn),
                        "locked": .bool(state.locked),
                        "battery_level": .double(state.batteryLevel)
                    ]),
                    bodyText: nil,
                    cacheControl: "no-store",
                    durationMS: 1,
                    errorMessage: nil,
                    method: "GET",
                    path: "/\(state.vin)/state",
                    query: [:],
                    requestID: "demo-export",
                    statusCode: 200,
                    timestamp: state.updatedAtMS,
                    url: "sandbox://demo-vehicle/\(state.vin)/state"
                )
            ],
            vin: state.vin
        )
    }

    // MARK: - Builders

    private static let demoCapabilities = FleetCapabilities(
        chargeActions: FleetDemoVehicleState.supportedControlActions.chargeActions,
        controlActions: FleetDemoVehicleState.supportedControlActions.actions,
        events: ["drive.started", "charging.started"],
        notificationEvents: ["drive.started", "charging.started"],
        scopes: ["vehicles:read", "vehicle_commands", "vehicle_history", "telemetry:read"]
    )

    private static func makeVehicle(from state: FleetDemoVehicleState) -> FleetVehicle {
        FleetVehicle(
            displayName: state.displayName,
            hidden: false,
            latest: makeSnapshot(from: state),
            permissions: ["control", "read"],
            vehicleTag: "demo",
            vin: state.vin
        )
    }

    private static func makeSnapshot(from state: FleetDemoVehicleState) -> FleetLatestSnapshot {
        FleetLatestSnapshot(
            batteryLevel: state.batteryLevel,
            batteryRange: state.batteryRangeMiles,
            chargeLimitSOC: state.chargeLimitSOC,
            chargeRateMPH: state.chargeRateMPH > 0 ? state.chargeRateMPH : nil,
            chargerPowerKW: state.chargerPowerKW > 0 ? state.chargerPowerKW : nil,
            chargePortDoorOpen: state.chargePortDoorOpen,
            chargingState: state.chargingState,
            climateOn: state.hvacOn,
            closures: FleetVehicleClosureState(
                frontDriverDoorOpen: false,
                frontDriverWindowOpen: state.frontDriverWindowOpen,
                frontPassengerDoorOpen: false,
                frontPassengerWindowOpen: state.frontPassengerWindowOpen,
                frontTrunkOpen: state.frontTrunkOpen,
                rearDriverDoorOpen: false,
                rearDriverWindowOpen: state.rearDriverWindowOpen,
                rearPassengerDoorOpen: false,
                rearPassengerWindowOpen: state.rearPassengerWindowOpen,
                rearTrunkOpen: state.rearTrunkOpen
            ),
            freshnessMS: 500,
            gear: "P",
            heading: 315,
            insideTemp: state.insideTempF,
            latitude: state.latitude,
            locked: state.locked,
            longitude: state.longitude,
            odometer: state.odometerMiles,
            outsideTemp: state.outsideTempF,
            sentryMode: state.sentryModeOn,
            software: makeSoftwareUpdate(from: state, includeReleaseNotes: true),
            speed: nil,
            targetTemperature: state.targetTempF,
            timeToFullCharge: state.timeToFullCharge > 0 ? state.timeToFullCharge : nil,
            timestamp: state.updatedAtMS,
            tires: FleetTirePressures(
                frontLeftPSI: state.frontLeftPSI,
                frontRightPSI: state.frontRightPSI,
                lastMeasuredAt: state.updatedAtMS,
                rearLeftPSI: state.rearLeftPSI,
                rearRightPSI: state.rearRightPSI
            ),
            updatedAt: state.updatedAtMS,
            vehicleConfiguration: FleetVehicleConfiguration(
                carType: state.carType,
                exteriorColor: state.exteriorColor,
                trimBadging: "74d",
                wheelType: "Apollo19"
            ),
            vin: state.vin
        )
    }

    private static func makeSoftwareUpdate(
        from state: FleetDemoVehicleState,
        includeReleaseNotes: Bool
    ) -> FleetSoftwareUpdate {
        let hasUpdate = state.availableSoftwareVersion != nil
        let isInstallable = hasUpdate && (state.softwareStatus == "available" || state.softwareStatus == "scheduled")
        let notes: [FleetSoftwareReleaseNote]
        if includeReleaseNotes {
            let targetVersion = state.availableSoftwareVersion ?? state.currentSoftwareVersion
            notes = FleetDemoVehicleState.demoReleaseNotes(version: targetVersion).map { note in
                FleetSoftwareReleaseNote(
                    description: note.details,
                    subtitle: note.subtitle,
                    title: note.title
                )
            }
        } else {
            notes = []
        }

        return FleetSoftwareUpdate(
            availableVersion: state.availableSoftwareVersion,
            currentVersion: state.currentSoftwareVersion,
            downloadPercent: hasUpdate ? 100 : nil,
            expectedDurationMinutes: hasUpdate ? 25 : nil,
            expectedDurationSec: hasUpdate ? 1_500 : nil,
            installPercent: state.softwareStatus == "installing" ? 15 : 0,
            installable: isInstallable,
            releaseNotes: notes,
            releaseNotesCount: notes.count,
            status: state.softwareStatus,
            updateAvailable: hasUpdate,
            updatedAt: state.updatedAtMS
        )
    }

    private static func makeChargingSessions(from state: FleetDemoVehicleState) -> [FleetChargeSession] {
        var sessions: [FleetChargeSession] = []
        if state.chargingState == "Charging" {
            sessions.append(
                FleetChargeSession(
                    avgPowerKW: state.chargerPowerKW,
                    batteryLevelEnd: nil,
                    batteryLevelStart: max(state.batteryLevel - 6, 10),
                    cost: 2.15,
                    currency: "USD",
                    durationMS: 1_800_000,
                    endedAt: nil,
                    energyAddedKWH: 5.8,
                    maxPowerKW: state.chargerPowerKW,
                    sessionID: "\(state.vin):demo-active-charge",
                    startedAt: state.updatedAtMS - 1_800_000,
                    status: "Charging",
                    vin: state.vin
                )
            )
        }
        let history = FleetDemoVehicleState.demoCharges(
            vin: state.vin,
            now: Date(timeIntervalSince1970: TimeInterval(state.updatedAtMS) / 1_000)
        )
        sessions.append(contentsOf: history.map { item in
            FleetChargeSession(
                avgPowerKW: item.isSupercharger ? 142.0 : 11.2,
                batteryLevelEnd: item.endingBatteryPercent.map(Double.init),
                batteryLevelStart: item.startingBatteryPercent.map(Double.init),
                cost: item.cost,
                currency: "USD",
                durationMS: item.endedAt.map { max($0 - item.startedAt, 0) },
                endedAt: item.endedAt,
                energyAddedKWH: item.energyAddedKWH,
                maxPowerKW: item.isSupercharger ? 248.0 : 11.5,
                sessionID: item.sessionID,
                startedAt: item.startedAt,
                status: "Complete",
                vin: item.vin
            )
        })
        return sessions
    }

    private static func makeDrives(vin: String, includeRoute: Bool, nowMS: Int64) -> [FleetDriveSession] {
        let route = includeRoute ? makeDemoRoute(startMS: nowMS - 14_400_000) : []
        return [
            FleetDriveSession(
                avgSpeedMPH: 33.7,
                distanceMiles: 14.6,
                durationMS: 1_560_000,
                endedAt: nowMS - 12_840_000,
                energyUsedKWH: 3.6,
                maxSpeedMPH: 64.0,
                route: route,
                sessionID: "\(vin):demo-102",
                startAddress: "1 Apple Park Way, Cupertino, CA",
                endAddress: "Palo Alto Caltrain, Palo Alto, CA",
                startLatitude: 37.3349,
                startLongitude: -122.0090,
                endLatitude: 37.4430,
                endLongitude: -122.1650,
                startedAt: nowMS - 14_400_000,
                vin: vin
            ),
            FleetDriveSession(
                avgSpeedMPH: 49.4,
                distanceMiles: 36.2,
                durationMS: 2_640_000,
                endedAt: nowMS - 95_360_000,
                energyUsedKWH: 9.2,
                maxSpeedMPH: 71.0,
                route: [],
                sessionID: "\(vin):demo-101",
                startAddress: "Palo Alto, CA",
                endAddress: "San Francisco International Airport, CA",
                startLatitude: 37.4430,
                startLongitude: -122.1650,
                endLatitude: 37.6213,
                endLongitude: -122.3790,
                startedAt: nowMS - 98_000_000,
                vin: vin
            )
        ]
    }

    private static func makeDemoRoute(startMS: Int64) -> [FleetRoutePoint] {
        let samples: [(lat: Double, lon: Double, speed: Double, heading: Double, fsd: String)] = [
            (37.3349, -122.0090, 0, 0, "Standby"),
            (37.3385, -122.0165, 28, 305, "Autosteer"),
            (37.3520, -122.0360, 56, 310, "Autosteer"),
            (37.3810, -122.0780, 62, 308, "Autosteer"),
            (37.4120, -122.1230, 48, 312, "Autosteer"),
            (37.4430, -122.1650, 0, 315, "Off")
        ]
        return samples.enumerated().map { index, item in
            FleetRoutePoint(
                latitude: item.lat,
                longitude: item.lon,
                odometer: 14_805.8 + Double(index) * 2.9,
                speed: item.speed,
                timestamp: startMS + Int64(index) * 300_000,
                heading: item.heading,
                autopilot: item.fsd
            )
        }
    }

    private static func convertParameters(_ params: [String: JSONValue]) -> [String: FleetControlValue] {
        var converted: [String: FleetControlValue] = [:]
        for (key, value) in params {
            switch value {
            case .string(let text):
                converted[key] = .string(text)
            case .integer(let number):
                converted[key] = .int(number)
            case .double(let number):
                converted[key] = .double(number)
            case .bool(let flag):
                converted[key] = .bool(flag)
            case .object, .array, .null:
                break
            }
        }
        return converted
    }

    private func makePage<Value>(
        _ data: Value,
        cursor: Int64? = nil,
        requestID: String
    ) -> FleetAPIPage<Value> {
        FleetAPIPage(
            data: data,
            cursor: cursor,
            cached: false,
            stale: false,
            requestID: requestID
        )
    }
}
