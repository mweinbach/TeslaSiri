import AppIntents
import CoreLocation
import FleetKit
import MapKit
import SwiftUI

/// At-a-glance cards under the Vehicle tab hero: live drive, battery, climate + security,
/// location, tires, and vehicle details.
struct VehicleTelemetryCards: View {
    let vehicle: FleetVehicle
    let units: String?
    let activeDrive: FleetActiveDriveSession?
    let chargingSessions: [FleetChargeSession]
    var includeLocation: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let activeDrive {
            VehicleLiveDriveCard(drive: activeDrive)
        }

        if let snapshot = vehicle.latest {
            VehicleBatteryCard(snapshot: snapshot, units: units, sessions: chargingSessions)

            let pairLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            pairLayout {
                VehicleClimateCard(snapshot: snapshot, units: units)
                VehicleSecurityCard(snapshot: snapshot)
            }
            .fixedSize(horizontal: false, vertical: true)

            if includeLocation, let latitude = snapshot.latitude, let longitude = snapshot.longitude {
                VehicleLocationCard(vehicleName: vehicle.name, latitude: latitude, longitude: longitude)
            }

            if let tires = snapshot.tires, tires.hasAnyReading {
                VehicleTiresCard(tires: tires)
            }

            VehicleDetailsCard(vehicle: vehicle, snapshot: snapshot, units: units)
        }
    }
}

// MARK: - Live drive

struct VehicleLiveDriveCard: View {
    let drive: FleetActiveDriveSession

    var body: some View {
        DashboardCard("Driving", systemImage: "location.north.fill", tint: .green) {
            if let status = drive.status {
                Text(humanizedStatus(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } content: {
            HStack(alignment: .lastTextBaseline) {
                MetricValueText(
                    value: formattedNumber(drive.latestRoutePoint?.speed ?? drive.latest?.speed, fractionLength: 0),
                    unit: "mph"
                )
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    if let distance = drive.distanceMiles {
                        miniStat(formattedNumber(distance, fractionLength: 1, suffix: " mi"), caption: "Distance")
                    }
                    if let durationMS = drive.durationMS, durationMS > 0 {
                        miniStat(formattedDuration(milliseconds: durationMS), caption: "Duration")
                    }
                }
            }
        }
        .appEntityIdentifier(driveEntityIdentifier)
    }

    private func miniStat(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var driveEntityIdentifier: EntityIdentifier? {
        guard !drive.sessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID)
    }
}

// MARK: - Battery

struct VehicleBatteryCard: View {
    let snapshot: FleetLatestSnapshot
    let units: String?
    let sessions: [FleetChargeSession]

    private var isCharging: Bool { snapshot.isActivelyCharging }

    var body: some View {
        DashboardCard("Battery", systemImage: batterySymbol, tint: isCharging ? .green : .secondary) {
            StatusBadge(
                plugStatusText,
                systemImage: isCharging ? "bolt.fill" : "powerplug",
                tint: isCharging ? .green : .secondary
            )
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline) {
                    MetricValueText(
                        value: formattedNumber(snapshot.batteryLevel, fractionLength: 0),
                        unit: "%"
                    )
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedRange)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("Estimated range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let level = snapshot.batteryLevel {
                    BatteryLevelBar(
                        level: level / 100,
                        limit: snapshot.chargeLimitSOC.map { $0 / 100 },
                        isCharging: isCharging
                    )
                }

                if isCharging {
                    chargingDetails
                }

                if !sessions.isEmpty {
                    Divider()
                    NavigationLink {
                        ChargingHistoryView(sessions: sessions)
                    } label: {
                        DashboardCardLinkLabel(
                            title: "Charging History",
                            systemImage: "clock.arrow.circlepath",
                            detail: "\(sessions.count)"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var chargingDetails: some View {
        HStack(spacing: 8) {
            if let power = snapshot.chargerPowerKW, power > 0 {
                detail(formattedNumber(power, fractionLength: 1, suffix: " kW"), caption: "Power")
            }
            if let rate = snapshot.chargeRateMPH, rate > 0 {
                let converted = units == "metric" ? rate * 1.609_344 : rate
                detail(
                    formattedNumber(converted, fractionLength: 0, suffix: units == "metric" ? " km/h" : " mi/h"),
                    caption: "Rate"
                )
            }
            if let remaining = snapshot.timeToFullCharge, remaining > 0 {
                detail(formattedNumber(remaining, fractionLength: 1, suffix: " hr"), caption: "To limit")
            }
        }
    }

    private func detail(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var plugStatusText: String {
        if let state = snapshot.chargingState, !state.isEmpty {
            return humanizedStatus(state)
        }
        return snapshot.chargePortDoorOpen == true ? "Port Open" : "Unplugged"
    }

    private var batterySymbol: String {
        if isCharging { return "battery.100.bolt" }
        let level = snapshot.batteryLevel ?? 0
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var formattedRange: String {
        guard let range = snapshot.batteryRange else { return "--" }
        let value = units == "metric" ? range * 1.609_344 : range
        return formattedNumber(value, fractionLength: 0, suffix: units == "metric" ? " km" : " mi")
    }
}

/// Capsule battery bar with a charge-limit marker.
private struct BatteryLevelBar: View {
    let level: Double
    let limit: Double?
    let isCharging: Bool

    private var clampedLevel: Double { max(0, min(level, 1)) }

    private var fillStyle: Color {
        if isCharging { return .green }
        if clampedLevel <= 0.15 { return .red }
        return clampedLevel <= 0.25 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = proxy.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.insetSurface)

                    Capsule()
                        .fill(fillStyle.gradient)
                        .frame(width: max(height, width * clampedLevel))
                        .animation(.smooth(duration: 0.35), value: clampedLevel)

                    if let limit {
                        let clampedLimit = max(0, min(limit, 1))
                        Capsule()
                            .fill(.primary.opacity(0.65))
                            .frame(width: 2.5, height: height + 6)
                            .offset(x: min(max(width * clampedLimit - 1.25, 0), width - 2.5))
                    }
                }
            }
            .frame(height: 12)

            if let limit {
                HStack {
                    Text("Charge limit \(formattedNumber(limit * 100, fractionLength: 0, suffix: "%"))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    if clampedLevel >= max(0, min(limit, 1)) - 0.01 {
                        Text("At limit")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var value = formattedNumber(clampedLevel * 100, fractionLength: 0, suffix: "%")
        if let limit {
            value += ", charge limit \(formattedNumber(limit * 100, fractionLength: 0, suffix: "%"))"
        }
        return value
    }
}

private struct ChargingHistoryView: View {
    let sessions: [FleetChargeSession]

    var body: some View {
        List(sessions) { session in
            ChargeHistoryRow(session: session)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Charging History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChargeHistoryRow: View {
    let session: FleetChargeSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAtDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let energy = session.energyAddedKWH {
                Text("+\(formattedNumber(energy, fractionLength: 1, suffix: " kWh"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            } else {
                Text(session.status.map(humanizedStatus) ?? "Charge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        // Same "<VIN>:<id>" identifier as FleetKit's ChargeSessionEntity, so Siri can
        // resolve "tell me about this charge" from the visible row.
        .appEntityIdentifier(EntityIdentifier(for: ChargeSessionEntity.self, identifier: session.sessionID))
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let start = session.batteryLevelStart, let end = session.batteryLevelEnd {
            parts.append("\(Int(start.rounded()))% → \(Int(end.rounded()))%")
        }
        if let power = session.avgPowerKW, power > 0 {
            parts.append(formattedNumber(power, fractionLength: 1, suffix: " kW avg"))
        }
        if let cost = session.cost, cost > 0 {
            parts.append(session.currency.map { cost.formatted(.currency(code: $0)) } ?? "Cost \(cost.formatted())")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Climate & security

struct VehicleClimateCard: View {
    let snapshot: FleetLatestSnapshot
    let units: String?

    private var isOn: Bool { snapshot.climateOn == true }

    var body: some View {
        DashboardCard("Climate", systemImage: isOn ? "fan.fill" : "fan", tint: isOn ? .blue : .secondary) {
            VStack(alignment: .leading, spacing: 4) {
                MetricValueText(value: formattedNumber(snapshot.insideTemp, fractionLength: 0, suffix: "°"))
                Text("Inside cabin")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 5) {
                    if let outside = snapshot.outsideTemp {
                        Label(
                            "\(formattedNumber(outside, fractionLength: 0, suffix: "°")) outside",
                            systemImage: "cloud.sun"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Label(statusText, systemImage: isOn ? "fan.fill" : "power")
                        .foregroundStyle(isOn ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                }
                .font(.footnote.weight(.medium))
                .labelStyle(CompactLabelStyle())
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        guard let on = snapshot.climateOn else { return "Unavailable" }
        guard on else { return "Off" }
        if let target = snapshot.targetTemperature {
            return "Set to \(formattedNumber(target, fractionLength: 0, suffix: "°"))"
        }
        return "On"
    }
}

struct VehicleSecurityCard: View {
    let snapshot: FleetLatestSnapshot

    private var isLocked: Bool { snapshot.locked == true }

    var body: some View {
        DashboardCard("Security", systemImage: "lock.shield", tint: isLocked ? .secondary : .orange) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.locked.map { $0 ? "Locked" : "Unlocked" } ?? "--")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(isLocked ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(isLocked ? "Doors secured" : (snapshot.locked == false ? "Doors openable" : "Status unavailable"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 5) {
                    let summary = closureSummary
                    Label(summary.text, systemImage: summary.symbol)
                        .foregroundStyle(summary.hasOpenItem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    if let sentry = snapshot.sentryMode {
                        Label(sentry ? "Sentry on" : "Sentry off", systemImage: sentry ? "eye.fill" : "eye.slash")
                            .foregroundStyle(sentry ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.footnote.weight(.medium))
                .labelStyle(CompactLabelStyle())
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var closureSummary: (text: String, symbol: String, hasOpenItem: Bool) {
        let c = snapshot.closures
        let groups: [(String, [Bool?])] = [
            ("Door", [c?.frontDriverDoorOpen, c?.frontPassengerDoorOpen, c?.rearDriverDoorOpen, c?.rearPassengerDoorOpen]),
            ("Frunk", [c?.frontTrunkOpen]),
            ("Trunk", [c?.rearTrunkOpen]),
            ("Window", [c?.frontDriverWindowOpen, c?.frontPassengerWindowOpen, c?.rearDriverWindowOpen, c?.rearPassengerWindowOpen]),
            ("Port", [snapshot.chargePortDoorOpen])
        ]
        let openItems = groups.filter { $0.1.contains(true) }.map(\.0)
        if !openItems.isEmpty {
            return ("\(openItems.formatted(.list(type: .and))) open", "exclamationmark.triangle.fill", true)
        }
        if groups.contains(where: { $0.1.contains(nil) }) {
            return ("Closure status incomplete", "questionmark.circle", false)
        }
        return ("All closed", "checkmark.circle", false)
    }
}

/// Tight icon + title label for the small status lines inside cards.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
                .imageScale(.small)
            configuration.title
                .lineLimit(2)
        }
    }
}

// MARK: - Location

struct VehicleLocationCard: View {
    let vehicleName: String
    let latitude: Double
    let longitude: Double
    var mapHeight: CGFloat = 176

    @State private var resolvedAddress: String?

    var body: some View {
        DashboardCard("Location", systemImage: "location.fill") {
            if let mapsURL {
                Link(destination: mapsURL) {
                    Label("Open in Maps", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.footnote.weight(.semibold))
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Map(
                    position: .constant(.camera(MapCamera(centerCoordinate: coordinate, distance: 900))),
                    interactionModes: []
                ) {
                    Marker(vehicleName, systemImage: "car.fill", coordinate: coordinate)
                        .tint(.red)
                }
                .mapControlVisibility(.hidden)
                .frame(height: mapHeight)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Map showing \(vehicleName)'s location")

                Text(resolvedAddress ?? coordinateTaskID)
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)
            }
            .task(id: coordinateTaskID) {
                let address = await driveEndpointAddressGeocoder.address(latitude: latitude, longitude: longitude)
                guard !Task.isCancelled else { return }
                if let address {
                    resolvedAddress = address
                }
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var coordinateTaskID: String {
        formattedCoordinate(latitude: latitude, longitude: longitude)
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: vehicleName)
        ]
        return components?.url
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}

// MARK: - Tires

struct VehicleTiresCard: View {
    let tires: FleetTirePressures

    private static let lowThresholdPSI = 38.0

    private var hasLowTire: Bool {
        [tires.frontLeftPSI, tires.frontRightPSI, tires.rearLeftPSI, tires.rearRightPSI]
            .compactMap { $0 }
            .contains { $0 < Self.lowThresholdPSI }
    }

    var body: some View {
        DashboardCard(
            "Tire Pressure",
            systemImage: hasLowTire ? "exclamationmark.tirepressure" : "tirepressure",
            tint: hasLowTire ? .orange : .secondary
        ) {
            if hasLowTire {
                StatusBadge("Low Tire", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            } else if let measured = tires.measuredAtDate {
                RelativeTimeText(date: measured)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } content: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 32) {
                    tireReading(tires.frontLeftPSI, position: "Front left", alignment: .leading)
                    tireReading(tires.rearLeftPSI, position: "Rear left", alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VehicleTopDownOutline(
                    lowFrontLeft: isLow(tires.frontLeftPSI),
                    lowFrontRight: isLow(tires.frontRightPSI),
                    lowRearLeft: isLow(tires.rearLeftPSI),
                    lowRearRight: isLow(tires.rearRightPSI)
                )
                .frame(width: 68, height: 124)
                .accessibilityHidden(true)

                VStack(alignment: .trailing, spacing: 32) {
                    tireReading(tires.frontRightPSI, position: "Front right", alignment: .trailing)
                    tireReading(tires.rearRightPSI, position: "Rear right", alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)
        }
    }

    private func isLow(_ psi: Double?) -> Bool {
        guard let psi else { return false }
        return psi < Self.lowThresholdPSI
    }

    private func tireReading(_ psi: Double?, position: String, alignment: HorizontalAlignment) -> some View {
        let low = isLow(psi)
        return VStack(alignment: alignment, spacing: 1) {
            MetricValueText(
                value: formattedNumber(psi, fractionLength: 1),
                unit: "psi",
                font: .system(.title2, design: .rounded, weight: .semibold),
                unitFont: .caption.weight(.semibold)
            )
            .foregroundStyle(low ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            Text(low ? "\(position) · Low" : position)
                .font(.caption)
                .foregroundStyle(low ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position) tire")
        .accessibilityValue(formattedNumber(psi, fractionLength: 1, suffix: low ? " psi, low" : " psi"))
    }
}

/// Top-down car silhouette with four wheel indicators beside tire readings.
private struct VehicleTopDownOutline: View {
    var lowFrontLeft: Bool = false
    var lowFrontRight: Bool = false
    var lowRearLeft: Bool = false
    var lowRearRight: Bool = false

    var body: some View {
        ZStack {
            wheel(offset: CGSize(width: -29, height: -34), isLow: lowFrontLeft)
            wheel(offset: CGSize(width: 29, height: -34), isLow: lowFrontRight)
            wheel(offset: CGSize(width: -29, height: 35), isLow: lowRearLeft)
            wheel(offset: CGSize(width: 29, height: 35), isLow: lowRearRight)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.insetSurface)
                .strokeBorder(AppTheme.hairline, lineWidth: 1.25)
                .frame(width: 54, height: 120)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 38, height: 26)
                .offset(y: -18)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.8))
                .frame(width: 36, height: 16)
                .offset(y: 30)
        }
    }

    private func wheel(offset: CGSize, isLow: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(isLow ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .frame(width: 8, height: 22)
            .offset(offset)
    }
}

// MARK: - Details

struct VehicleDetailsCard: View {
    let vehicle: FleetVehicle
    let snapshot: FleetLatestSnapshot
    let units: String?

    var body: some View {
        DashboardCard("Vehicle", systemImage: "car.fill") {
            VStack(spacing: 0) {
                let rows = detailRows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    LabeledContent(row.label) {
                        Text(row.value)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 9)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var detailRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        let config = snapshot.vehicleConfiguration
        if let model = config?.humanizedModelName {
            rows.append(("Model", model))
        }
        if let trim = config?.humanizedTrimName {
            rows.append(("Trim", trim))
        }
        if let paint = config?.humanizedPaintName {
            rows.append(("Paint", paint))
        }
        if let wheels = config?.humanizedWheelName {
            rows.append(("Wheels", wheels))
        }
        if let odometer = snapshot.odometer {
            let value = units == "metric" ? odometer * 1.609_344 : odometer
            rows.append(("Odometer", formattedNumber(value, fractionLength: 0, suffix: units == "metric" ? " km" : " mi")))
        }
        if !vehicle.vin.isEmpty {
            rows.append(("VIN", vehicle.vin))
        }
        return rows
    }
}
