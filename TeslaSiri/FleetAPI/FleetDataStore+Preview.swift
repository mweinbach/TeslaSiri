import Foundation

extension FleetDataStore {
    static func previewLoaded() -> FleetDataStore {
        let store = FleetDataStore(apiClient: PreviewFleetDataClient())
        let now = Date()
        let vin = PreviewFleetDataClient.previewVIN
        let previewRoute = PreviewFleetDataClient.previewDriveRoute

        let previewState = FleetCachedState(
            activeCharging: [
                FleetChargeSession(
                    avgPowerKW: 42.1,
                    batteryLevelEnd: nil,
                    batteryLevelStart: 38,
                    cost: nil,
                    currency: nil,
                    durationMS: nil,
                    endedAt: nil,
                    energyAddedKWH: 18.4,
                    maxPowerKW: 97.2,
                    sessionID: "preview-charge",
                    startedAt: 1_781_000_000_000,
                    status: "active",
                    vin: vin
                )
            ],
            activeDrivesByVIN: [
                vin: FleetActiveDriveSession(
                    durationMS: 540_000,
                    latest: FleetLatestSnapshot(
                        speed: 32,
                        timestamp: 1_781_000_540_000,
                        updatedAt: 1_781_000_540_000,
                        vin: vin
                    ),
                    latestRoutePoint: previewRoute.last,
                    route: previewRoute,
                    routePointCount: previewRoute.count,
                    sessionID: "preview-active-drive",
                    startedAt: 1_781_000_000_000,
                    vin: vin
                )
            ],
            capabilities: FleetCapabilities(
                chargeActions: ["set_charge_limit"],
                controlActions: ["wake", "flash_lights"],
                events: ["drive.started"],
                notificationEvents: ["drive.started", "charging.started"],
                scopes: ["vehicles:read", "telemetry:read"]
            ),
            cursor: 1_781_000_100_000,
            driveRoutesBySessionID: ["preview-drive": previewRoute],
            locationHistoryByVIN: [vin: previewRoute],
            recentDrives: [
                FleetDriveSession(
                    avgSpeedMPH: 34,
                    distanceMiles: 12.4,
                    durationMS: 1_620_000,
                    endedAt: 1_781_001_620_000,
                    energyUsedKWH: 3.1,
                    maxSpeedMPH: 58,
                    route: previewRoute,
                    sessionID: "preview-drive",
                    startAddress: "1 Apple Park Way, Cupertino, CA",
                    endAddress: "Infinite Loop, Cupertino, CA",
                    startedAt: 1_781_000_000_000,
                    vin: vin
                )
            ],
            savedAt: now,
            selectedVIN: vin,
            softwareUpdatesByVIN: [
                vin: FleetSoftwareUpdate(
                    availableVersion: "2026.20",
                    currentVersion: "2026.14.6",
                    downloadPercent: 100,
                    expectedDurationMinutes: 25,
                    expectedDurationSec: 1_500,
                    installPercent: 0,
                    installable: true,
                    releaseNotes: [
                        FleetSoftwareReleaseNote(
                            description: "Adds software update state and release notes to the debug backend view.",
                            subtitle: "Release notes",
                            title: "Software updates"
                        )
                    ],
                    releaseNotesCount: 1,
                    status: "available",
                    updateAvailable: true,
                    updatedAt: 1_781_000_000_000
                )
            ],
            telemetrySeriesByVIN: [
                vin: [["timestamp": 1_781_000_000_000, "speed": 0, "battery_level": 74]]
            ],
            user: FleetUser(
                email: "driver@example.com",
                name: "Driver",
                scopes: ["vehicles:read", "telemetry:read"],
                units: "imperial"
            ),
            vehicles: [
                FleetVehicle(
                    displayName: "Model 3",
                    latest: FleetLatestSnapshot(
                        batteryLevel: 74,
                        batteryRange: 260,
                        chargeLimitSOC: 80,
                        chargeRateMPH: 28,
                        chargerPowerKW: 7.2,
                        chargingState: "Charging",
                        climateOn: true,
                        freshnessMS: 1_500,
                        gear: nil,
                        insideTemp: 70,
                        latitude: 37.3349,
                        locked: true,
                        longitude: -122.0090,
                        odometer: 19_204,
                        outsideTemp: 64,
                        sentryMode: false,
                        speed: nil,
                        targetTemperature: 72,
                        timeToFullCharge: 1.4,
                        timestamp: 1_781_000_000_000,
                        updatedAt: 1_781_000_000_000,
                        vin: vin
                    ),
                    permissions: ["control"],
                    vehicleTag: "daily",
                    vin: vin
                )
            ]
        )

        store.applySnapshotState(previewState, isCached: false)
        return store
    }
}

private struct PreviewFleetDataClient: FleetDataLoading {
    static let previewVIN = "5YJ3E1EA7JF000001"

    static let previewDriveRoute = FleetDataNormalizer.routePoints([
        FleetRoutePoint(latitude: 37.3318, longitude: -122.0312, odometer: 19_204.0, speed: 0, timestamp: 1_781_000_000),
        FleetRoutePoint(latitude: 37.3324, longitude: -122.0307, odometer: 19_204.2, speed: 18, timestamp: 1_781_000_180_000),
        FleetRoutePoint(latitude: 37.3333, longitude: -122.0297, odometer: 19_204.5, speed: 32, timestamp: 1_781_000_360_000),
        FleetRoutePoint(latitude: 37.3342, longitude: -122.0282, odometer: 19_204.9, speed: 41, timestamp: 1_781_000_540_000),
        FleetRoutePoint(latitude: 37.3354, longitude: -122.0270, odometer: 19_205.2, speed: 37, timestamp: 1_781_000_720_000),
        FleetRoutePoint(latitude: 37.3361, longitude: -122.0259, odometer: 19_205.5, speed: 24, timestamp: 1_781_000_900_000),
        FleetRoutePoint(latitude: 37.3364, longitude: -122.0251, odometer: 19_205.7, speed: 0, timestamp: 1_781_001_080_000),
        FleetRoutePoint(latitude: 91, longitude: -122.0251, odometer: 19_205.8, speed: -4, timestamp: 1_781_001_090_000),
        FleetRoutePoint(latitude: 37.3364, longitude: -122.0251, odometer: 19_205.7, speed: 0, timestamp: 1_781_001_080_000)
    ])

    func bootstrap() async throws -> FleetAPIPage<FleetBootstrap> {
        makePage(data: FleetBootstrap(), cursor: 1_781_000_100_000, requestID: "preview")
    }

    func capabilities() async throws -> FleetAPIPage<FleetCapabilities> {
        makePage(
            data: FleetCapabilities(scopes: ["vehicles:read", "telemetry:read"]),
            requestID: "preview-capabilities"
        )
    }

    func changes(since cursor: Int64, refresh: Bool) async throws -> FleetAPIPage<FleetSyncChanges> {
        makePage(data: FleetSyncChanges(), cursor: cursor + 1, requestID: "preview")
    }

    func wakeVehicle(vin: String) async throws {}

    func latestSnapshot(vin: String, includingTires: Bool, refresh: Bool) async throws -> FleetAPIPage<FleetLatestSnapshot> {
        makePage(data: FleetLatestSnapshot(vin: vin), requestID: "preview-live")
    }

    func runControl(
        action: String,
        vin: String,
        params: [String: JSONValue]
    ) async throws -> FleetAPIPage<[String: JSONValue]> {
        makePage(data: ["result": true], requestID: "preview-control-\(action)")
    }

    func activeDrive(
        vin: String,
        includeRoute: Bool,
        routeMaxPoints: Int?
    ) async throws -> FleetAPIPage<FleetActiveDriveSession> {
        makePage(
            data: FleetActiveDriveSession(active: false, vin: vin),
            requestID: "preview-active-drive"
        )
    }

    func drives(vin: String, limit: Int?, includeRoute: Bool) async throws -> FleetAPIPage<[FleetDriveSession]> {
        let drive = FleetDriveSession(
            distanceMiles: 1.7,
            durationMS: 1_080_000,
            endedAt: 1_781_001_080_000,
            energyUsedKWH: 0.6,
            route: includeRoute ? Self.previewDriveRoute : [],
            sessionID: "preview-drive",
            startAddress: "1 Apple Park Way, Cupertino, CA",
            endAddress: "Infinite Loop, Cupertino, CA",
            startedAt: 1_781_000_000_000,
            vin: vin
        )
        return makePage(data: [drive], requestID: "preview-drives")
    }

    func driveRoute(
        sessionID: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?,
        maxPoints: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        makePage(data: Self.previewDriveRoute, requestID: "preview-route")
    }

    func chargingSessions(vin: String, limit: Int?) async throws -> FleetAPIPage<[FleetChargeSession]> {
        makePage(data: [], requestID: "preview-charging")
    }

    func softwareUpdate(
        vin: String,
        includeReleaseNotes: Bool,
        refresh: Bool
    ) async throws -> FleetAPIPage<FleetSoftwareUpdate> {
        makePage(
            data: FleetSoftwareUpdate(
                currentVersion: "2026.14.6",
                installable: false,
                updateAvailable: false
            ),
            requestID: "preview-software"
        )
    }

    func installSoftwareUpdate(vin: String, offsetSec: Int) async throws -> FleetAPIPage<[String: JSONValue]> {
        makePage(data: ["requested": true], requestID: "preview-software-install")
    }

    func cancelSoftwareUpdate(vin: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        makePage(data: ["canceled": true], requestID: "preview-software-cancel")
    }

    func locations(
        vin: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        makePage(data: [], requestID: "preview-locations")
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
        makePage(data: [], requestID: "preview-telemetry")
    }

    func rawVehicleDataExport(vin: String) async throws -> FleetRawDataExport {
        FleetRawDataExport(
            apiBaseURL: "https://api.tessie.com",
            appSchemaVersion: 2,
            generatedAt: 1_781_000_000_000,
            responses: [
                FleetRawAPIResponse(
                    apiVersion: "1.0",
                    body: .object([
                        "ok": true,
                        "data": .object([
                            "vin": .string(vin),
                            "inside_temp": 70,
                            "outside_temp": 64,
                            "route_points": .array([
                                .object([
                                    "latitude": 37.3318,
                                    "longitude": -122.0312,
                                    "speed": 0,
                                    "timestamp": 1_781_000_000_000
                                ])
                            ])
                        ])
                    ]),
                    bodyText: nil,
                    cacheControl: "no-store",
                    durationMS: 12,
                    errorMessage: nil,
                    method: "GET",
                    path: "/\(vin)/state",
                    query: [:],
                    requestID: "preview-raw",
                    statusCode: 200,
                    timestamp: 1_781_000_000_000,
                    url: "https://api.tessie.com/\(vin)/state"
                )
            ],
            vin: vin
        )
    }

    private func makePage<T>(
        data: T,
        cursor: Int64? = nil,
        requestID: String
    ) -> FleetAPIPage<T> {
        FleetAPIPage(
            data: data,
            cursor: cursor,
            cached: false,
            stale: false,
            requestID: requestID
        )
    }
}
