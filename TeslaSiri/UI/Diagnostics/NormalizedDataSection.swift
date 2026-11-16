import AppIntents
import FleetKit
import SwiftUI

struct NormalizedDataSection: View {
    let store: FleetDataStore

    var body: some View {
        CardContainer(title: "Normalized Data", systemImage: "doc.text.magnifyingglass") {
            if let vehicle = store.selectedVehicle {
                VStack(alignment: .leading, spacing: 12) {
                    DiagnosticMonospacedValue(title: "Selected VIN", value: vehicle.vin)
                        .appEntityIdentifier(vehicleEntityIdentifier(for: vehicle.vin))
                    DiagnosticRow(label: "Units", value: unitDescription)
                    DiagnosticRow(label: "Temperature display", value: temperatureSuffix.trimmingCharacters(in: .whitespaces))
                    DiagnosticRow(label: "Live snapshot", value: snapshotSummary(vehicle.latest))
                        .appEntityIdentifier(statusEntityIdentifier(for: vehicle.latest))
                    DiagnosticRow(label: "Tire pressure", value: vehicle.latest?.tires?.displaySummary ?? "None")
                    DiagnosticRow(label: "Software source", value: softwareSource(for: vehicle))

                    if let software = store.selectedVehicleSoftwareUpdate {
                        DiagnosticRow(label: "Software", value: softwareSummary(software))
                            .appEntityIdentifier(softwareEntityIdentifier(for: vehicle.vin))
                    }

                    if let activeDrive = store.selectedVehicleActiveDrive {
                        Group {
                            DiagnosticRow(label: "Active drive", value: activeDriveSummary(activeDrive))
                            DiagnosticRow(label: "Route samples", value: routeSampleSummary(activeDrive.route))
                            DiagnosticRow(label: "Buffered samples", value: "\(activeDrive.bufferedPoints.count)")
                            DiagnosticRow(label: "Start location", value: formattedCoordinate(latitude: activeDrive.startLocation?.latitude, longitude: activeDrive.startLocation?.longitude))
                            DiagnosticRow(label: "Latest route point", value: formattedCoordinate(latitude: activeDrive.latestRoutePoint?.latitude, longitude: activeDrive.latestRoutePoint?.longitude))
                        }
                        .appEntityIdentifier(driveEntityIdentifier(for: activeDrive))
                    } else {
                        DiagnosticRow(label: "Active drive", value: store.isLoadingActiveDrive ? "Loading" : "None")
                    }

                    if store.supportsContinuousHistory {
                        DiagnosticRow(label: "Location history", value: routeSampleSummary(store.selectedVehicleLocationHistory))
                        DiagnosticRow(label: "Telemetry series", value: telemetrySummary)
                        ForEach(telemetryFieldRows) { row in
                            DiagnosticMonospacedValue(title: row.key, value: row.value)
                        }
                    } else {
                        DiagnosticRow(label: "Location and telemetry history", value: "Available per drive")
                    }
                }
            } else {
                Label("No selected vehicle", systemImage: "car")
                    .foregroundStyle(.secondary)
            }
        }
        .appEntityIdentifier(selectedVehicleEntityIdentifier)
    }

    private var selectedVehicleEntityIdentifier: EntityIdentifier? {
        guard let vin = store.selectedVehicle?.vin else { return nil }
        return vehicleEntityIdentifier(for: vin)
    }

    private func vehicleEntityIdentifier(for vin: String) -> EntityIdentifier? {
        guard !vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleEntity.self, identifier: vin)
    }

    private func statusEntityIdentifier(for snapshot: FleetLatestSnapshot?) -> EntityIdentifier? {
        guard let vin = snapshot?.vin, !vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleStatusEntity.self, identifier: VehicleStatusEntity.entityID(forVIN: vin))
    }

    private func softwareEntityIdentifier(for vin: String) -> EntityIdentifier? {
        guard !vin.isEmpty else { return nil }
        return EntityIdentifier(for: SoftwareUpdateEntity.self, identifier: SoftwareUpdateEntity.entityID(forVIN: vin))
    }

    private func driveEntityIdentifier(for drive: FleetActiveDriveSession) -> EntityIdentifier? {
        guard !drive.sessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID)
    }

    private var unitDescription: String {
        store.user?.units?.capitalized ?? "--"
    }

    private var temperatureSuffix: String {
        store.user?.units == "metric" ? " C" : " F"
    }

    private var telemetrySummary: String {
        let points = store.selectedVehicleTelemetrySeries
        guard let firstPoint = points.first else {
            return points.isEmpty ? "No points" : "\(points.count) points"
        }
        let keys = firstPoint.fields.keys.sorted().prefix(6).joined(separator: ", ")
        return keys.isEmpty ? "\(points.count) points" : "\(points.count) points; \(keys)"
    }

    private var telemetryFieldRows: [DiagnosticFieldRow] {
        guard let point = store.selectedVehicleTelemetrySeries.first else {
            return []
        }
        return point.fields.keys.sorted().prefix(8).compactMap { key in
            point.fields[key].map { DiagnosticFieldRow(key: key, value: formattedJSONValue($0)) }
        }
    }

    private func snapshotSummary(_ snapshot: FleetLatestSnapshot?) -> String {
        guard let snapshot else {
            return "None"
        }
        let updated = snapshot.updatedAtDate?.formatted(date: .abbreviated, time: .shortened) ?? "--"
        let battery = formattedNumber(snapshot.batteryLevel, suffix: "%")
        return "\(battery), updated \(updated)"
    }

    private func softwareSource(for vehicle: FleetVehicle) -> String {
        let hasDedicatedSoftware = store.softwareUpdatesByVIN[vehicle.vin] != nil
        let hasSnapshotSoftware = vehicle.latest?.software != nil
        switch (hasDedicatedSoftware, hasSnapshotSoftware) {
        case (true, true):
            return "Dedicated + live"
        case (true, false):
            return "Dedicated endpoint"
        case (false, true):
            return "Live snapshot"
        case (false, false):
            return "None"
        }
    }

    private func softwareSummary(_ software: FleetSoftwareUpdate) -> String {
        if let availableVersion = software.availableVersion, availableVersion != software.currentVersion {
            return "\(software.currentVersion ?? "--") -> \(availableVersion)"
        }
        return software.currentVersion ?? software.status ?? "Present"
    }

    private func activeDriveSummary(_ drive: FleetActiveDriveSession) -> String {
        let routeCount = drive.routePointCount ?? drive.route.count
        let duration = formattedDuration(milliseconds: drive.durationMS)
        return "\(routeCount) route, \(duration)"
    }

    private func routeSampleSummary(_ points: [FleetRoutePoint]) -> String {
        guard let first = points.first, let last = points.last else {
            return "No points"
        }
        if first.id == last.id {
            return formattedCoordinate(latitude: first.latitude, longitude: first.longitude)
        }
        return "\(formattedCoordinate(latitude: first.latitude, longitude: first.longitude)) -> \(formattedCoordinate(latitude: last.latitude, longitude: last.longitude))"
    }
}

struct DiagnosticFieldRow: Identifiable {
    let key: String
    let value: String

    var id: String { key }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview("With selected vehicle") {
    NormalizedDataSection(store: FleetDataStore.previewLoaded())
        .padding()
        .background(AppScreenBackground())
}
