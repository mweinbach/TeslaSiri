import AppIntents
import Foundation
import SwiftUI

/// Rich, self-contained Siri dynamic snippet for vehicle status, featuring a visual
/// battery & charge-limit gauge, an embedded Apple Maps parked-car location card,
/// a 2×2 telemetry bento grid, and live quick controls.
public struct VehicleStatusSnippetView: View {
    public let status: VehicleStatusEntity
    public let mapData: SiriRenderedMapData?
    let topics: Set<VehicleInfoTopic>

    public init(
        status: VehicleStatusEntity,
        mapData: SiriRenderedMapData? = nil,
        topics: Set<VehicleInfoTopic> = Set(VehicleInfoTopic.allCases)
    ) {
        self.status = status
        self.mapData = mapData
        self.topics = topics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if !topics.isDisjoint(with: [.battery, .range, .charging]) {
                batteryCard
            }

            if topics.contains(.location), hasLocationCard {
                parkedLocationMapCard
            }

            if !topics.isDisjoint(with: [.climate, .tirePressure, .odometer, .security]) {
                bentoGrid
            }

            if !status.id.isEmpty {
                quickControlsRow
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: VehicleStatusEntity.self, identifier: status.id))
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 8) {
            Label(status.vehicleName, systemImage: "car.fill")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if topics.contains(.security), let isLocked = status.isLocked {
                Label(
                    isLocked ? "Locked" : "Unlocked",
                    systemImage: isLocked ? "lock.fill" : "lock.open.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }

            if topics.contains(.security), status.sentryModeOn == true {
                Image(systemName: "record.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Sentry Mode On")
            }
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: batterySymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(batteryColor)

                if topics == [.range] {
                    Text(status.batteryRangeMiles.map { "\(Int($0.rounded())) mi" } ?? "Range unavailable")
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                } else {
                    Text(status.batteryDisplay)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if topics.contains(.range), topics != [.range], let range = status.batteryRangeMiles {
                    Text("· \(Int(range.rounded())) mi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if topics.contains(.charging), let state = status.chargingState, !state.isEmpty {
                    chargingBadge(for: state)
                }
            }

            if let pct = status.batteryPercent {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let clampedPct = min(max(Double(pct) / 100.0, 0), 1)
                    let limitFraction = min(max(Double(status.chargeLimitPercent ?? 80) / 100.0, 0), 1)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [batteryColor.opacity(0.85), batteryColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(width * clampedPct, 8))

                        if status.chargeLimitPercent != nil {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(.primary.opacity(0.75))
                                .frame(width: 2.5, height: 14)
                                .offset(x: min(max(width * limitFraction - 1.25, 0), width - 2.5))
                        }
                    }
                }
                .frame(height: 10)
            }

            HStack {
                if let limit = status.chargeLimitPercent {
                    Text("Charge limit \(limit)%")
                        .monospacedDigit()
                }
                Spacer()
                if let power = status.chargerPowerKW, power > 0.2 {
                    Text(String(format: "%.1f kW", power))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                } else if let minutes = status.minutesToFullCharge, minutes > 0 {
                    Text("\(minutes)m to limit")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chargingBadge(for state: String) -> some View {
        let isCharging = state.localizedStandardContains("charging") && !state.localizedStandardContains("dis")
        return Label(state.capitalized, systemImage: isCharging ? "bolt.fill" : "powerplug")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCharging ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    private var hasLocationCard: Bool {
        mapData != nil || status.locationAddress != nil || (status.latitude != nil && status.longitude != nil)
    }

    private var parkedLocationMapCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = mapData?.swiftUIImage {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        SiriVectorRouteFallbackView(points: fallbackPinPoints)
                    }
                }
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipped()

                Button(intent: ToggleSnippetMapStyleIntent(scope: "vehicle")) {
                    Label(currentMapStyle.badgeLabel, systemImage: currentMapStyle.badgeIcon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            HStack(spacing: 8) {
                Image(systemName: speedBadgeSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(locationHeadline)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let sub = locationSubheadline {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if let url = appleMapsCarURL {
                    Link(destination: url) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.16), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.55))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.75)
        )
    }

    private var bentoGrid: some View {
        let unit = status.temperatureUnit ?? "°F"
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            if topics.contains(.climate) || topics.contains(.tirePressure) {
                GridRow {
                    if topics.contains(.climate) {
                        bentoTile(
                            icon: status.isClimateOn == true ? "fan.fill" : "thermometer.medium",
                            title: "Cabin",
                            value: status.insideTemp.map { "\(Int($0.rounded()))\(unit)" } ?? "—",
                            subtitle: status.outsideTemp.map { "Out \(Int($0.rounded()))\(unit)" }
                                ?? status.isClimateOn.map { $0 ? "Climate On" : "Climate Off" },
                            accent: status.isClimateOn == true ? .orange : .secondary
                        )
                    }
                    if topics.contains(.tirePressure) {
                        bentoTile(
                            icon: hasLowTire ? "exclamationmark.tirepressure" : "car.side.rear.and.tire.marks",
                            title: "Tires",
                            value: compactTireRange ?? "—",
                            subtitle: hasLowTire ? "Check pressure" : status.tireSummary,
                            accent: hasLowTire ? .orange : .secondary
                        )
                    }
                }
            }

            if topics.contains(.odometer) || topics.contains(.security) {
                GridRow {
                    if topics.contains(.odometer) {
                        bentoTile(
                            icon: "gauge.with.needle",
                            title: "Odometer",
                            value: status.odometerDisplay ?? "—",
                            subtitle: updatedSubtitle,
                            accent: .secondary
                        )
                    }
                    if topics.contains(.security) {
                        bentoTile(
                            icon: hasOpenClosures ? "car.top.door.front.left.open" : "checkmark.shield.fill",
                            title: "Closures",
                            value: status.openClosures.map { $0 == "None" ? "All Closed" : $0 } ?? "—",
                            subtitle: status.sentryModeOn.map { $0 ? "Sentry Active" : "Sentry Off" },
                            accent: hasOpenClosures ? .orange : .green
                        )
                    }
                }
            }
        }
    }

    private func bentoTile(icon: String, title: String, value: String, subtitle: String?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(accent)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var quickControlsRow: some View {
        HStack(spacing: 8) {
            if status.isLocked == true {
                Button(intent: unlockIntent) {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
            } else if status.isLocked == false {
                Button(intent: lockIntent) {
                    Label("Lock", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
            }

            Button(intent: startClimateIntent) {
                Label(status.isClimateOn == true ? "Warming" : "Climate", systemImage: "fan.fill")
                    .frame(maxWidth: .infinity)
            }

            Button(intent: honkIntent) {
                Label("Honk", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private var currentMapStyle: SiriMapVisualStyle {
        mapData?.style ?? SiriSnippetStateStore.shared.mapStyle(for: "vehicle")
    }

    private var fallbackPinPoints: [FleetDriveRoutePoint] {
        if let pts = mapData?.points, !pts.isEmpty {
            return pts
        }
        if let lat = status.latitude, let lon = status.longitude {
            return [FleetDriveRoutePoint(latitude: lat, longitude: lon)]
        }
        return [FleetDriveRoutePoint(latitude: 37.3346, longitude: -122.0090)]
    }

    private var speedBadgeSymbol: String {
        if let speed = status.speedMPH, speed > 1 {
            return "location.north.line.fill"
        }
        return "parkingsign.circle.fill"
    }

    private var locationHeadline: String {
        if let address = status.locationAddress, !address.isEmpty {
            return address
        }
        if let lat = status.latitude, let lon = status.longitude {
            return String(format: "%.4f, %.4f", lat, lon)
        }
        return "\(status.vehicleName) Location"
    }

    private var locationSubheadline: String? {
        if let speed = status.speedMPH, speed > 1 {
            return "Driving · \(Int(speed.rounded())) mph"
        }
        if let gear = status.gear, !gear.isEmpty {
            return gear == "P" ? "Parked · Apple Maps" : "Gear \(gear) · Apple Maps"
        }
        return "Parked · Apple Maps"
    }

    private var appleMapsCarURL: URL? {
        if let lat = status.latitude, let lon = status.longitude {
            let label = status.vehicleName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Car"
            return URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=w&q=\(label)")
        }
        if let address = status.locationAddress,
           let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=w")
        }
        return nil
    }

    private var allTirePSIs: [Double] {
        [status.frontLeftTirePSI, status.frontRightTirePSI, status.rearLeftTirePSI, status.rearRightTirePSI]
            .compactMap { $0 }
    }

    private var hasLowTire: Bool {
        allTirePSIs.contains { $0 < 37.0 }
    }

    private var compactTireRange: String? {
        let psis = allTirePSIs
        guard let minPSI = psis.min(), let maxPSI = psis.max() else {
            return status.tireSummary
        }
        let minInt = Int(minPSI.rounded())
        let maxInt = Int(maxPSI.rounded())
        return minInt == maxInt ? "\(minInt) PSI" : "\(minInt)–\(maxInt) PSI"
    }

    private var hasOpenClosures: Bool {
        guard let closures = status.openClosures, !closures.isEmpty else { return false }
        return closures.caseInsensitiveCompare("None") != .orderedSame
    }

    private var updatedSubtitle: String? {
        guard let updatedAt = status.updatedAt else { return nil }
        return "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var vehicle: VehicleEntity {
        VehicleEntity(id: status.vin, name: status.vehicleName)
    }

    private var lockIntent: LockVehicleIntent {
        let intent = LockVehicleIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var unlockIntent: UnlockVehicleIntent {
        let intent = UnlockVehicleIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var startClimateIntent: StartClimateIntent {
        let intent = StartClimateIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var honkIntent: HonkHornIntent {
        let intent = HonkHornIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var batteryColor: Color {
        switch status.batteryPercent ?? 50 {
        case ..<20: .red
        case ..<35: .orange
        default: .green
        }
    }

    private var batterySymbol: String {
        switch status.batteryPercent ?? 0 {
        case ..<20: "battery.25percent"
        case ..<60: "battery.50percent"
        case ..<90: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: - Interactive Cabin Climate Siri Widget

/// Dynamic Siri widget displayed after warming up, cooling down, or configuring cabin climate,
/// complete with current-to-target temperature readout, active comfort badges, and live +/- controls.
public struct ClimateControlSnippetView: View {
    public let vehicle: VehicleEntity
    public let status: VehicleStatusEntity?
    public let appliedSummary: String
    private let receipt: ClimateCommandReceipt?
    private let interactionID: String?
    private let sessionScope: String?

    public init(vehicle: VehicleEntity, status: VehicleStatusEntity?, appliedSummary: String) {
        self.init(vehicle: vehicle, status: status, appliedSummary: appliedSummary, receipt: nil,
                  interactionID: nil, sessionScope: FleetIntentService.make().sessionScopeID)
    }

    init(vehicle: VehicleEntity, status: VehicleStatusEntity?, appliedSummary: String,
         receipt: ClimateCommandReceipt?, interactionID: String?, sessionScope: String?) {
        self.vehicle = vehicle
        self.status = status
        self.appliedSummary = appliedSummary
        self.receipt = receipt
        self.interactionID = interactionID
        self.sessionScope = sessionScope
    }

    public var body: some View {
        let isRunning = displayedRunning
        let unit = displayUnit == .celsius ? "°C" : "°F"
        let currentTargetF = displayedTarget?.converted(to: .fahrenheit).value

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(vehicle.name, systemImage: isRunning == false ? "fan.slash.fill" : "fan.fill")
                    .font(.headline)
                    .foregroundStyle(isRunning == true ? AnyShapeStyle(thermalAccent) : AnyShapeStyle(.primary))

                Spacer()

                if let isRunning {
                    Text(isRunning ? "Conditioning" : "Climate Off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isRunning ? AnyShapeStyle(thermalAccent) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            (isRunning ? thermalAccent.opacity(0.16) : Color.secondary.opacity(0.14)),
                            in: Capsule()
                        )
                }
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(displayedTarget.map { "\($0.value.formatted(.number.precision(.fractionLength(0...1))))\(unit)" } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(isRunning == true ? AnyShapeStyle(thermalAccent) : AnyShapeStyle(.primary))
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let inside = status?.insideTemp {
                        Label("Cabin \(Int(inside.rounded()))\(unit)", systemImage: "car.fill")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    if let outside = status?.outsideTemp {
                        Label("Outside \(Int(outside.rounded()))\(unit)", systemImage: "cloud.sun.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let updated = status?.updatedAt, status?.insideTemp != nil || status?.outsideTemp != nil {
                        Text("Observed \(updated, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: isRunning == true
                        ? [thermalAccent.opacity(0.18), thermalAccent.opacity(0.05)]
                        : [Color.secondary.opacity(0.10), Color.secondary.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            if !comfortBadges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(comfortBadges, id: \.title) { badge in
                        Label(badge.title, systemImage: badge.icon)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            } else {
                Text(appliedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !vehicle.id.isEmpty {
                HStack(spacing: 8) {
                    if let currentTargetF {
                        Button(intent: adjust(targetFahrenheit: currentTargetF - 2)) {
                            Label("Cooler", systemImage: "minus")
                                .frame(maxWidth: .infinity)
                        }
                        Button(intent: adjust(targetFahrenheit: currentTargetF + 2)) {
                            Label("Warmer", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let isRunning {
                        Button(intent: adjust(turnOff: isRunning)) {
                            Label(isRunning ? "Off" : "Turn On", systemImage: isRunning ? "power" : "fan.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: VehicleEntity.self, identifier: vehicle.id))
    }

    private func adjust(targetFahrenheit: Double? = nil, turnOff: Bool = false) -> AdjustSnippetClimateIntent {
        AdjustSnippetClimateIntent(vehicle: vehicle, targetFahrenheit: targetFahrenheit, turnOff: turnOff,
                                  interactionID: interactionID, scope: sessionScope)
    }

    private var displayUnit: UnitTemperature {
        switch status?.temperatureUnit {
        case "°C": .celsius
        case "°F": .fahrenheit
        default: Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        }
    }

    private func observationIsNewer(than commandDate: Date?) -> Bool {
        guard let date = status?.updatedAt, let commandDate else { return false }
        return date > commandDate
    }

    var displayedTarget: Measurement<UnitTemperature>? {
        if let target = status?.targetTemp, status?.temperatureUnit != nil,
           observationIsNewer(than: receipt?.targetSetAt) || receipt?.targetCelsius == nil {
            return Measurement(value: target, unit: displayUnit)
        }
        return receipt?.targetCelsius.map { Measurement(value: $0, unit: .celsius).converted(to: displayUnit) }
    }

    var displayedRunning: Bool? {
        if observationIsNewer(than: receipt?.date), let observed = status?.isClimateOn { return observed }
        return receipt?.running ?? status?.isClimateOn
    }

    private var thermalAccent: Color {
        if let inside = status?.insideTemp, let target = displayedTarget, inside > target.value + 2 { return .cyan }
        return .orange
    }

    private var comfortBadges: [(title: String, icon: String)] {
        var items: [(String, String)] = []
        if status?.maxDefrostOn == true {
            items.append(("Max Defrost", "windshield.front.and.heat.waves"))
        }
        if status?.steeringWheelHeaterOn == true {
            items.append(("Wheel Heat", "steeringwheel.and.heat.waves"))
        }
        if let seats = status?.seatHeaterSummary,
           seats.contains(where: { $0 == "1" || $0 == "2" || $0 == "3" }) {
            items.append(("Seat Heat", "carseat.left.and.heat.waves.fill"))
        }
        if status?.dogModeOn == true {
            items.append(("Dog Mode", "pawprint.fill"))
        }
        return items
    }
}

