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
    /// The location card appears only when the presenter asks for it. `status` can carry the
    /// car's position even when the request that produced the card wasn't allowed to show it.
    let showsLocation: Bool

    public init(
        status: VehicleStatusEntity,
        mapData: SiriRenderedMapData? = nil,
        topics: Set<VehicleInfoTopic> = Set(VehicleInfoTopic.allCases),
        showsLocation: Bool = false
    ) {
        self.status = status
        self.mapData = mapData
        self.topics = topics
        self.showsLocation = showsLocation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if !topics.isDisjoint(with: [.battery, .range, .charging]) {
                batteryCard
            }

            if hasLocationCard {
                parkedLocationMapCard
            }

            if !topics.isDisjoint(with: [.climate, .tirePressure, .odometer, .security]) {
                bentoGrid
            }

            if !status.id.isEmpty {
                quickControlsRow
            }
        }
        .padding(12)
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
                Label {
                    if isLocked {
                        Text("Locked", bundle: .module, comment: "Vehicle lock status badge: locked")
                    } else {
                        Text("Unlocked", bundle: .module, comment: "Vehicle lock status badge: unlocked")
                    }
                } icon: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }

            if topics.contains(.security), status.sentryModeOn == true {
                Image(systemName: "record.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("Sentry Mode On", bundle: .module, comment: "Accessibility label for active Sentry Mode icon"))
            }
        }
    }

    private var batteryCard: some View {
        let metric = status.usesMetric
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: batterySymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(batteryColor)

                if topics == [.range] {
                    Text(
                        status.batteryRangeMiles.map { FleetKitFormatting.distance(miles: $0, usesMetric: metric) }
                            ?? String(localized: "Range unavailable", bundle: .module, comment: "Fallback when vehicle range is unknown")
                    )
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(status.batteryDisplay)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if topics.contains(.range), topics != [.range], let range = status.batteryRangeMiles {
                    Text(verbatim: "· \(FleetKitFormatting.distance(miles: range, usesMetric: metric))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                if topics.contains(.charging), let label = status.chargingStateLabel {
                    chargingBadge(label, isCharging: status.chargingState == .charging)
                }
            }

            if let pct = status.batteryPercent {
                let clampedPct = min(max(Double(pct) / 100.0, 0), 1)
                let limitFraction = min(max(Double(status.chargeLimitPercent ?? 80) / 100.0, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    FractionalCapsuleBar(fraction: clampedPct, minimumWidth: 8)
                        .fill(
                            LinearGradient(
                                colors: [batteryColor.opacity(0.85), batteryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    if status.chargeLimitPercent != nil {
                        FractionalTickMark(fraction: limitFraction, tickWidth: 2.5, tickHeight: 14)
                            .fill(.primary.opacity(0.75))
                    }
                }
                .flipsForRightToLeftLayoutDirection(true)
                .frame(height: 10)
            }

            HStack {
                if let limit = status.chargeLimitPercent {
                    let limitPct = FleetKitFormatting.percent(limit)
                    Text("Charge limit \(limitPct)", bundle: .module, comment: "Battery charge limit caption on Siri status card")
                        .monospacedDigit()
                }
                Spacer()
                if let power = status.chargerPowerKW, power > 0.2 {
                    Text(FleetKitFormatting.powerKW(power))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                } else if let minutes = status.minutesToFullCharge, minutes > 0 {
                    let duration = FleetKitFormatting.durationMinutes(minutes)
                    Text("\(duration) to limit", bundle: .module, comment: "Remaining charging duration until charge limit is reached")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chargingBadge(_ label: String, isCharging: Bool) -> some View {
        Label(label, systemImage: isCharging ? "bolt.fill" : "powerplug")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(isCharging ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    var hasLocationCard: Bool {
        showsLocation
            && (mapData != nil || status.locationAddress != nil || (status.latitude != nil && status.longitude != nil))
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
                .frame(height: 96)
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
                        Label {
                            Text("Directions", bundle: .module, comment: "Button to open walking directions to parked car in Apple Maps")
                        } icon: {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        }
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
        let inFahrenheit = status.temperatureUnit != "°C"
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            if topics.contains(.climate) || topics.contains(.tirePressure) {
                GridRow {
                    if topics.contains(.climate) {
                        bentoTile(
                            icon: status.isClimateOn == true ? "fan.fill" : "thermometer.medium",
                            title: LocalizedStringResource("Cabin", bundle: FleetKitLocalization.bundleDescription, comment: "Cabin temperature tile header"),
                            value: status.insideTemp.map { FleetKitFormatting.temperature($0, inFahrenheit: inFahrenheit) } ?? "—",
                            subtitle: status.outsideTemp.map {
                                let outTemp = FleetKitFormatting.temperature($0, inFahrenheit: inFahrenheit)
                                return String(localized: "Out \(outTemp)", bundle: .module, comment: "Abbreviated outside temperature subtitle")
                            }
                                ?? status.isClimateOn.map {
                                    $0
                                        ? String(localized: "Climate On", bundle: .module, comment: "Cabin tile subtitle when climate is on")
                                        : String(localized: "Climate Off", bundle: .module, comment: "Cabin tile subtitle when climate is off")
                                },
                            accent: status.isClimateOn == true ? .orange : .secondary
                        )
                    }
                    if topics.contains(.tirePressure) {
                        bentoTile(
                            icon: hasLowTire ? "exclamationmark.tirepressure" : "car.side.rear.and.tire.marks",
                            title: LocalizedStringResource("Tires", bundle: FleetKitLocalization.bundleDescription, comment: "Tire pressure tile header"),
                            value: compactTireRange ?? "—",
                            subtitle: hasLowTire
                                ? String(localized: "Check pressure", bundle: .module, comment: "Low tire pressure warning subtitle")
                                : status.tireSummary,
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
                            title: LocalizedStringResource("Odometer", bundle: FleetKitLocalization.bundleDescription, comment: "Odometer mileage tile header"),
                            value: status.odometerDisplay ?? "—",
                            subtitle: updatedSubtitle,
                            accent: .secondary
                        )
                    }
                    if topics.contains(.security) {
                        bentoTile(
                            icon: hasOpenClosures ? "car.top.door.front.left.open" : "checkmark.shield.fill",
                            title: LocalizedStringResource("Closures", bundle: FleetKitLocalization.bundleDescription, comment: "Doors, windows, and trunks status tile header"),
                            value: status.openClosures.map {
                                $0 == "None"
                                    ? String(localized: "All Closed", bundle: .module, comment: "Closures status when all doors, windows, and trunks are closed")
                                    : $0
                            } ?? "—",
                            subtitle: status.sentryModeOn.map {
                                $0
                                    ? String(localized: "Sentry Active", bundle: .module, comment: "Closures tile subtitle when Sentry Mode is active")
                                    : String(localized: "Sentry Off", bundle: .module, comment: "Closures tile subtitle when Sentry Mode is off")
                            },
                            accent: hasOpenClosures ? .orange : .green
                        )
                    }
                }
            }
        }
    }

    private func bentoTile(icon: String, title: LocalizedStringResource, value: String, subtitle: String?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
                    Label {
                        Text("Unlock", bundle: .module, comment: "Quick control button to unlock vehicle")
                    } icon: {
                        Image(systemName: "lock.open.fill")
                    }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            } else if status.isLocked == false {
                Button(intent: lockIntent) {
                    Label {
                        Text("Lock", bundle: .module, comment: "Quick control button to lock vehicle")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            }

            Button(intent: startClimateIntent) {
                Label {
                    if status.isClimateOn == true {
                        Text("Warming", bundle: .module, comment: "Quick control button label when cabin climate is running")
                    } else {
                        Text("Climate", bundle: .module, comment: "Quick control button label to start cabin climate")
                    }
                } icon: {
                    Image(systemName: "fan.fill")
                }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }

            Button(intent: honkIntent) {
                Label {
                    Text("Honk", bundle: .module, comment: "Quick control button to honk vehicle horn")
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
        return String(localized: "\(status.vehicleName) Location", bundle: .module, comment: "Fallback location headline on vehicle map card")
    }

    private var locationSubheadline: String? {
        if let speed = status.speedMPH, speed > 1 {
            let speedText = FleetKitFormatting.speed(mph: speed, usesMetric: status.usesMetric)
            return String(localized: "Driving · \(speedText)", bundle: .module, comment: "Map card subtitle when the car is moving")
        }
        if let gear = status.gear, !gear.isEmpty {
            return gear == "P"
                ? String(localized: "Parked · Apple Maps", bundle: .module, comment: "Map card subtitle when the car is parked")
                : String(localized: "Gear \(gear) · Apple Maps", bundle: .module, comment: "Map card subtitle showing active gear")
        }
        return String(localized: "Parked · Apple Maps", bundle: .module, comment: "Map card subtitle when the car is parked")
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
        let metric = status.usesMetric
        let minText = FleetKitFormatting.tirePressure(psi: minPSI, usesMetric: metric)
        let maxText = FleetKitFormatting.tirePressure(psi: maxPSI, usesMetric: metric)
        if minText == maxText { return minText }
        if metric {
            let minBar = (minPSI * 0.0689476).formatted(.number.precision(.fractionLength(1)))
            return "\(minBar)–\(maxText)"
        }
        let minInt = Int(minPSI.rounded())
        return "\(minInt)–\(maxText)"
    }

    private var hasOpenClosures: Bool {
        guard let closures = status.openClosures, !closures.isEmpty else { return false }
        return closures.caseInsensitiveCompare("None") != .orderedSame
    }

    private var updatedSubtitle: String? {
        guard let updatedAt = status.updatedAt else { return nil }
        let formattedTime = updatedAt.formatted(date: .omitted, time: .shortened)
        return String(localized: "Updated \(formattedTime)", bundle: .module, comment: "Timestamp subtitle showing when telemetry was last updated")
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
        let waking = isWaking
        let inFahrenheit = displayUnit != .celsius
        let coolerTargetF: Double? = displayedTarget.map { target in
            if displayUnit == .celsius {
                return Measurement(value: target.converted(to: .celsius).value - 1, unit: UnitTemperature.celsius)
                    .converted(to: .fahrenheit).value
            }
            return target.converted(to: .fahrenheit).value - 2
        }
        let warmerTargetF: Double? = displayedTarget.map { target in
            if displayUnit == .celsius {
                return Measurement(value: target.converted(to: .celsius).value + 1, unit: UnitTemperature.celsius)
                    .converted(to: .fahrenheit).value
            }
            return target.converted(to: .fahrenheit).value + 2
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(vehicle.name, systemImage: waking ? "moon.zzz.fill" : (isRunning == false ? "fan.slash.fill" : "fan.fill"))
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(waking ? AnyShapeStyle(Color.orange) : (isRunning == true ? AnyShapeStyle(thermalAccent) : AnyShapeStyle(.primary)))

                Spacer()

                if waking {
                    Text("Waking Car…", bundle: .module, comment: "Climate card status badge while waking the car")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Color.orange.opacity(0.16),
                            in: Capsule()
                        )
                } else if let isRunning {
                    Group {
                        if isRunning {
                            Text("Conditioning", bundle: .module, comment: "Climate card status badge when cabin climate is running")
                        } else {
                            Text("Climate Off", bundle: .module, comment: "Climate card status badge when cabin climate is off")
                        }
                    }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
                    Text("Target", bundle: .module, comment: "Label above target cabin temperature")
                        .textCase(.uppercase)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(displayedTarget.map {
                        $0.formatted(
                            .measurement(
                                width: .abbreviated,
                                usage: .asProvided,
                                numberFormatStyle: .number.precision(.fractionLength(0...1))
                            )
                        )
                    } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(isRunning == true ? AnyShapeStyle(thermalAccent) : AnyShapeStyle(.primary))
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let inside = status?.insideTemp {
                        let temp = FleetKitFormatting.temperature(inside, inFahrenheit: inFahrenheit)
                        Label {
                            Text("Cabin \(temp)", bundle: .module, comment: "Current inside cabin temperature readout")
                        } icon: {
                            Image(systemName: "car.fill")
                        }
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    if let outside = status?.outsideTemp {
                        let temp = FleetKitFormatting.temperature(outside, inFahrenheit: inFahrenheit)
                        Label {
                            Text("Outside \(temp)", bundle: .module, comment: "Current outside temperature readout")
                        } icon: {
                            Image(systemName: "cloud.sun.fill")
                        }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let updated = status?.updatedAt, status?.insideTemp != nil || status?.outsideTemp != nil {
                        let formattedTime = updated.formatted(.dateTime.hour().minute())
                        Text("Observed \(formattedTime)", bundle: .module, comment: "Timestamp showing when temperature reading was observed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: waking
                        ? [Color.orange.opacity(0.16), Color.orange.opacity(0.05)]
                        : (isRunning == true
                            ? [thermalAccent.opacity(0.18), thermalAccent.opacity(0.05)]
                            : [Color.secondary.opacity(0.10), Color.secondary.opacity(0.04)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            if !waking, !comfortBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(comfortBadges, id: \.title) { badge in
                            Label(badge.title, systemImage: badge.icon)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
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
                    if let coolerTargetF, let warmerTargetF {
                        Button(intent: adjust(targetFahrenheit: coolerTargetF)) {
                            Label {
                                Text("Cooler", bundle: .module, comment: "Button to lower cabin target temperature")
                            } icon: {
                                Image(systemName: "minus")
                            }
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        Button(intent: adjust(targetFahrenheit: warmerTargetF)) {
                            Label {
                                Text("Warmer", bundle: .module, comment: "Button to raise cabin target temperature")
                            } icon: {
                                Image(systemName: "plus")
                            }
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let isRunning {
                        Button(intent: adjust(turnOff: isRunning)) {
                            Label {
                                if isRunning {
                                    Text("Off", bundle: .module, comment: "Button to turn off cabin climate")
                                } else {
                                    Text("Turn On", bundle: .module, comment: "Button to turn on cabin climate")
                                }
                            } icon: {
                                Image(systemName: isRunning ? "power" : "fan.fill")
                            }
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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

    var isWaking: Bool {
        receipt?.isWaking == true && !observationIsNewer(than: receipt?.date)
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
            items.append((String(localized: "Max Defrost", bundle: .module, comment: "Active comfort badge for Max Defrost"), "windshield.front.and.heat.waves"))
        }
        if status?.steeringWheelHeaterOn == true {
            items.append((String(localized: "Wheel Heat", bundle: .module, comment: "Active comfort badge for steering wheel heater"), "steeringwheel.and.heat.waves"))
        }
        if let seats = status?.seatHeaterSummary,
           seats.contains(where: { $0 == "1" || $0 == "2" || $0 == "3" }) {
            items.append((String(localized: "Seat Heat", bundle: .module, comment: "Active comfort badge for seat heaters"), "carseat.left.and.heat.waves.fill"))
        }
        if status?.dogModeOn == true {
            items.append((String(localized: "Dog Mode", bundle: .module, comment: "Active comfort badge for Dog Mode"), "pawprint.fill"))
        }
        return items
    }
}

// MARK: - Snippet Layout Helpers (GeometryReader-Free)

/// Proportional capsule segment drawn purely via `Shape` so Siri snippets and static
/// `CardSnippet` views size cleanly without `GeometryReader`.
struct FractionalCapsuleBar: Shape {
    let startFraction: Double
    let endFraction: Double
    let minimumWidth: CGFloat
    let leadingGap: CGFloat
    let trailingGap: CGFloat

    init(
        fraction: Double,
        minimumWidth: CGFloat = 8,
        leadingGap: CGFloat = 0,
        trailingGap: CGFloat = 0
    ) {
        self.startFraction = 0
        self.endFraction = min(max(fraction, 0), 1)
        self.minimumWidth = minimumWidth
        self.leadingGap = leadingGap
        self.trailingGap = trailingGap
    }

    init(
        startFraction: Double,
        endFraction: Double,
        minimumWidth: CGFloat = 6,
        leadingGap: CGFloat = 0,
        trailingGap: CGFloat = 0
    ) {
        self.startFraction = min(max(startFraction, 0), 1)
        self.endFraction = min(max(endFraction, 0), 1)
        self.minimumWidth = minimumWidth
        self.leadingGap = leadingGap
        self.trailingGap = trailingGap
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let lo = min(startFraction, endFraction)
        let hi = max(startFraction, endFraction)
        guard hi > lo else { return Path() }
        let x = min(rect.minX + rect.width * lo + leadingGap, rect.maxX)
        let rawEnd = max(rect.minX + rect.width * hi - trailingGap, x)
        let maxAvailable = max(rect.maxX - x - trailingGap, 0)
        let width = min(max(rawEnd - x, minimumWidth), maxAvailable)
        guard width > 0 else { return Path() }
        return Capsule().path(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height))
    }
}

/// Vertical tick mark positioned proportionally across a gauge bar without `GeometryReader`.
struct FractionalTickMark: Shape {
    let fraction: Double
    let tickWidth: CGFloat
    let tickHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0 else { return Path() }
        let clamped = min(max(fraction, 0), 1)
        let x = min(max(rect.minX + rect.width * clamped - tickWidth / 2, rect.minX), rect.maxX - tickWidth)
        let y = rect.midY - tickHeight / 2
        return RoundedRectangle(cornerRadius: tickWidth / 2).path(
            in: CGRect(x: x, y: y, width: tickWidth, height: tickHeight)
        )
    }
}

/// Conditionally attaches `.appEntityIdentifier` so shared snippet views can omit it
/// when rendered inside purely static `CardSnippet` contexts.
struct OptionalEntityIdentifierModifier: ViewModifier {
    let identifier: EntityIdentifier?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.appEntityIdentifier(identifier)
        } else {
            content
        }
    }
}


