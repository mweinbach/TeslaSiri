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
        HStack(spacing: 18) {
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
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        return clampedLevel <= 0.2 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    Capsule()
                        .fill(fillStyle.gradient)
                        .frame(width: max(proxy.size.height, width * clampedLevel))

                    if let limit {
                        Capsule()
                            .fill(.primary.opacity(0.55))
                            .frame(width: 2.5, height: proxy.size.height + 8)
                            .offset(x: width * max(0, min(limit, 1)) - 1.25)
                    }
                }
            }
            .frame(height: 12)

            if let limit {
                GeometryReader { proxy in
                    let x = proxy.size.width * max(0, min(limit, 1))
                    Text("Limit \(formattedNumber(limit * 100, fractionLength: 0, suffix: "%"))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(x, 32), proxy.size.width - 32), y: proxy.size.height / 2)
                }
                .frame(height: 14)
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
    private var tempSuffix: String { units == "metric" ? "°C" : "°F" }

    var body: some View {
        DashboardCard("Climate", systemImage: isOn ? "fan.fill" : "fan", tint: isOn ? .blue : .secondary) {
            VStack(alignment: .leading, spacing: 4) {
                MetricValueText(value: formattedNumber(snapshot.insideTemp, fractionLength: 0, suffix: "°"))
                Text("Inside")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 4) {
                    if let outside = snapshot.outsideTemp {
                        Label(
                            "\(formattedNumber(outside, fractionLength: 0, suffix: "°")) outside",
                            systemImage: "cloud.sun"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Label(statusText, systemImage: "power")
                        .foregroundStyle(isOn ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                }
                .font(.footnote.weight(.medium))
                .labelStyle(CompactLabelStyle())
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        guard let on = snapshot.climateOn else { return "Climate status unavailable" }
        guard on else { return "Climate off" }
        if let target = snapshot.targetTemperature {
            return "On · \(formattedNumber(target, fractionLength: 0, suffix: "°"))"
        }
        return "Climate on"
    }
}

struct VehicleSecurityCard: View {
    let snapshot: FleetLatestSnapshot

    private var isLocked: Bool { snapshot.locked == true }

    var body: some View {
        DashboardCard("Security", systemImage: "lock.shield", tint: isLocked ? .secondary : .orange) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: snapshot.locked.map { $0 ? "lock.fill" : "lock.open.fill" } ?? "lock.shield")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isLocked ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
                    .frame(height: 40, alignment: .bottomLeading)
                    .accessibilityHidden(true)
                Text(snapshot.locked.map { $0 ? "Locked" : "Unlocked" } ?? "Lock status unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 4) {
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
                resolvedAddress = nil
                let address = await driveEndpointAddressGeocoder.address(latitude: latitude, longitude: longitude)
                guard !Task.isCancelled else { return }
                resolvedAddress = address
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

    var body: some View {
        DashboardCard("Tire Pressure", systemImage: "tirepressure") {
            if let measured = tires.measuredAtDate {
                RelativeTimeText(date: measured)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } content: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 36) {
                    tireReading(tires.frontLeftPSI, position: "Front left", alignment: .leading)
                    tireReading(tires.rearLeftPSI, position: "Rear left", alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VehicleTopDownOutline()
                    .frame(width: 64, height: 120)
                    .accessibilityHidden(true)

                VStack(alignment: .trailing, spacing: 36) {
                    tireReading(tires.frontRightPSI, position: "Front right", alignment: .trailing)
                    tireReading(tires.rearRightPSI, position: "Rear right", alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)
        }
    }

    private func tireReading(_ psi: Double?, position: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            MetricValueText(
                value: formattedNumber(psi, fractionLength: 1),
                unit: "psi",
                font: .system(.title2, design: .rounded, weight: .semibold),
                unitFont: .caption.weight(.semibold)
            )
            Text(position)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position) tire")
        .accessibilityValue(formattedNumber(psi, fractionLength: 1, suffix: " psi"))
    }
}

/// Simple top-down car silhouette with four wheels, used beside tire readings.
private struct VehicleTopDownOutline: View {
    var body: some View {
        ZStack {
            ForEach(Array(Self.wheelOffsets.enumerated()), id: \.offset) { _, offset in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.secondary)
                    .frame(width: 8, height: 22)
                    .offset(offset)
            }

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.insetSurface)
                .strokeBorder(.tertiary, lineWidth: 1.5)
                .frame(width: 54, height: 118)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .frame(width: 40, height: 24)
                .offset(y: -20)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 38, height: 14)
                .offset(y: 34)
        }
    }

    private static let wheelOffsets: [CGSize] = [
        CGSize(width: -29, height: -34),
        CGSize(width: 29, height: -34),
        CGSize(width: -29, height: 36),
        CGSize(width: 29, height: 36)
    ]
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
