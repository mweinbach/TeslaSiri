import Foundation

/// Abstraction over Fleet/Tessie API endpoints consumed by `FleetDataStore`.
protocol FleetDataLoading {
    // MARK: - Bootstrap & Sync

    func bootstrap() async throws -> FleetAPIPage<FleetBootstrap>
    func capabilities() async throws -> FleetAPIPage<FleetCapabilities>
    func changes(since cursor: Int64, refresh: Bool) async throws -> FleetAPIPage<FleetSyncChanges>

    // MARK: - Live Snapshot & Vehicle Controls

    func wakeVehicle(vin: String) async throws
    func latestSnapshot(vin: String, includingTires: Bool, refresh: Bool) async throws -> FleetAPIPage<FleetLatestSnapshot>
    func runControl(
        action: String,
        vin: String,
        params: [String: JSONValue]
    ) async throws -> FleetAPIPage<[String: JSONValue]>

    // MARK: - Drives, Routes & Charging

    func activeDrive(
        vin: String,
        includeRoute: Bool,
        routeMaxPoints: Int?
    ) async throws -> FleetAPIPage<FleetActiveDriveSession>
    func drives(vin: String, limit: Int?, includeRoute: Bool) async throws -> FleetAPIPage<[FleetDriveSession]>
    func driveRoute(
        sessionID: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?,
        maxPoints: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]>
    func chargingSessions(vin: String, limit: Int?) async throws -> FleetAPIPage<[FleetChargeSession]>

    // MARK: - Software Updates

    func softwareUpdate(
        vin: String,
        includeReleaseNotes: Bool,
        refresh: Bool
    ) async throws -> FleetAPIPage<FleetSoftwareUpdate>
    func installSoftwareUpdate(vin: String, offsetSec: Int) async throws -> FleetAPIPage<[String: JSONValue]>
    func cancelSoftwareUpdate(vin: String) async throws -> FleetAPIPage<[String: JSONValue]>

    // MARK: - Telemetry & Diagnostics Export

    func locations(
        vin: String,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?
    ) async throws -> FleetAPIPage<[FleetRoutePoint]>
    func telemetrySeries(
        vin: String,
        topic: String?,
        startTime: Int64?,
        endTime: Int64?,
        limit: Int?,
        maxPoints: Int?,
        fields: [String]
    ) async throws -> FleetAPIPage<[FleetTelemetrySeriesPoint]>
    func rawVehicleDataExport(vin: String) async throws -> FleetRawDataExport
}

extension FleetDataLoading {
    func changes(since cursor: Int64) async throws -> FleetAPIPage<FleetSyncChanges> {
        try await changes(since: cursor, refresh: false)
    }

    func latestSnapshot(vin: String, includingTires: Bool) async throws -> FleetAPIPage<FleetLatestSnapshot> {
        try await latestSnapshot(vin: vin, includingTires: includingTires, refresh: false)
    }
}

extension FleetAPIClient: FleetDataLoading {}
