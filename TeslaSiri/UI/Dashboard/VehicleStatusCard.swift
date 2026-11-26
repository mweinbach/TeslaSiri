import AppIntents
import FleetKit
import SwiftUI

struct VehicleStatusCard: View {
    let vehicleName: String
    let snapshot: FleetLatestSnapshot?
    let units: String?

    var body: some View {
        Group {
            if let snapshot {
                VehicleStatusHero(
                    vehicleName: vehicleName,
                    snapshot: snapshot,
                    units: units
                )
            } else {
                CardContainer(title: vehicleName, systemImage: "car.side.fill") {
                    ContentUnavailableView(
                        "No live telemetry",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Pull to refresh or check your connection.")
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .appEntityIdentifier(statusEntityIdentifier)
    }

    private var statusEntityIdentifier: EntityIdentifier? {
        guard let vin = snapshot?.vin, !vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleStatusEntity.self, identifier: VehicleStatusEntity.entityID(forVIN: vin))
    }
}

private struct VehicleStatusHero: View {
    let vehicleName: String
    let snapshot: FleetLatestSnapshot
    let units: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VehicleHeroHeader(
                vehicleName: vehicleName,
                vin: snapshot.vin,
                updatedAt: snapshot.updatedAtDate
            )

            BatterySummary(snapshot: snapshot, units: units)

            StatusBadgesRow(snapshot: snapshot)

            MetricsGrid(snapshot: snapshot, units: units)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.055, green: 0.065, blue: 0.085),
                                Color(red: 0.10, green: 0.12, blue: 0.17)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color.accentColor.opacity(0.28))
                    .frame(width: 190, height: 190)
                    .blur(radius: 36)
                    .offset(x: 75, y: -85)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 116, weight: .regular))
                    .foregroundStyle(.white.opacity(0.055))
                    .offset(x: 48, y: 74)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 12)
    }
}

private struct VehicleHeroHeader: View {
    let vehicleName: String
    let vin: String
    let updatedAt: Date?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    updateStatus
                }
            } else {
                HStack(spacing: 12) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    updateStatus
                }
            }
        }
        .appEntityIdentifier(vehicleEntityIdentifier)
    }

    @ViewBuilder
    private var vehicleIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                vehicleIcon
                vehicleLabels
            }
        } else {
            HStack(spacing: 12) {
                vehicleIcon
                vehicleLabels
            }
        }
    }

    private var vehicleIcon: some View {
        Image(systemName: "car.side.fill")
            .font(.title3)
            .padding(10)
            .background(Color.white.opacity(0.10), in: Circle())
    }

    private var vehicleLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vehicleName)
                .font(.title3.weight(.bold))
            Text("Vehicle overview")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        if let updatedAt {
            HStack(spacing: 7) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    private var vehicleEntityIdentifier: EntityIdentifier? {
        guard !vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleEntity.self, identifier: vin)
    }
}

private struct BatterySummary: View {
    let snapshot: FleetLatestSnapshot
    let units: String?

    private var isCharging: Bool {
        snapshot.chargingState?.localizedCaseInsensitiveContains("charging") == true
    }

    private var batteryColor: Color {
        if isCharging {
            return .green
        }
        if let level = snapshot.batteryLevel, level <= 20 {
            return .orange
        }
        return .white
    }

    private var progress: Double {
        max(0, min((snapshot.batteryLevel ?? 0) / 100, 1))
    }

    private var summary: String {
        if isCharging, let timeToFull = snapshot.timeToFullCharge, timeToFull > 0 {
            let duration = Duration.seconds(Int((timeToFull * 3_600).rounded())).formatted(
                .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
            )
            return String(localized: "Charging · \(duration) remaining", comment: "Battery summary while charging with remaining time")
        }
        if let speed = snapshot.speed, speed > 0 {
            let speedText = formattedSpeed(mph: speed, units: units)
            return String(localized: "Driving · \(speedText)", comment: "Battery summary while driving with current speed")
        }
        return String(localized: "Battery", comment: "Battery label in vehicle status hero")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    batteryReading
                    Spacer()
                    chargeStats
                }

                VStack(alignment: .leading, spacing: 12) {
                    batteryReading
                    chargeStats
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProgressView(value: progress)
                .tint(batteryColor)
                .background(Color.white.opacity(0.12), in: Capsule())
                .accessibilityLabel("Battery level")
                .accessibilityValue(formattedPercent(snapshot.batteryLevel))
        }
    }

    private var batteryReading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedPercent(snapshot.batteryLevel))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(batteryColor)
                .contentTransition(.numericText())

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.70))
        }
    }

    @ViewBuilder
    private var chargeStats: some View {
        if snapshot.chargeRateMPH != nil || snapshot.chargerPowerKW != nil {
            VStack(alignment: .trailing, spacing: 3) {
                if let rate = snapshot.chargeRateMPH {
                    Text(formattedSpeed(mph: rate, units: units))
                        .font(.headline)
                        .monospacedDigit()
                }
                if let power = snapshot.chargerPowerKW {
                    Text(formattedPowerKW(power))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
    }
}

private struct StatusBadgesRow: View {
    let snapshot: FleetLatestSnapshot

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    badges
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        badges
                    }
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let state = snapshot.chargingState {
            StatusBadge(humanizedStatus(state), systemImage: "bolt.fill", tint: .orange)
        }
        if let locked = snapshot.locked {
            StatusBadge(
                locked ? LocalizedStringKey("Locked") : LocalizedStringKey("Unlocked"),
                systemImage: locked ? "lock.fill" : "lock.open.fill",
                tint: locked ? .green : .orange
            )
        }
        if let sentry = snapshot.sentryMode {
            StatusBadge(
                sentry ? LocalizedStringKey("Sentry on") : LocalizedStringKey("Sentry off"),
                systemImage: "shield.lefthalf.filled",
                tint: sentry ? .blue : .gray
            )
        }
        if let gear = snapshot.gear {
            StatusBadge(gear, systemImage: "car.fill", tint: .purple)
        }
    }
}

private struct MetricsGrid: View {
    let snapshot: FleetLatestSnapshot
    let units: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Metric: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let value: String
        let systemImage: String

        init(_ id: String, title: LocalizedStringKey, _ value: String, _ systemImage: String) {
            self.id = id
            self.title = title
            self.value = value
            self.systemImage = systemImage
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 132), spacing: 10)]
    }

    private var isFahrenheit: Bool {
        !prefersMetricUnits(units)
    }

    private var metrics: [Metric] {
        var items: [Metric] = []
        if let limit = snapshot.chargeLimitSOC {
            items.append(Metric("charge_limit", title: "Charge limit", formattedPercent(limit), "battery.100"))
        }
        if let speed = snapshot.speed {
            items.append(Metric("speed", title: "Speed", formattedSpeed(mph: speed, units: units), "speedometer"))
        }
        if let inside = snapshot.insideTemp {
            items.append(Metric("cabin", title: "Cabin", formattedTemperature(inside, inFahrenheit: isFahrenheit), "thermometer.medium"))
        }
        if let outside = snapshot.outsideTemp {
            items.append(Metric("outside", title: "Outside", formattedTemperature(outside, inFahrenheit: isFahrenheit), "thermometer.medium.slash"))
        }
        if let timeToFull = snapshot.timeToFullCharge, timeToFull > 0 {
            let duration = Duration.seconds(Int((timeToFull * 3_600).rounded())).formatted(
                .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
            )
            items.append(Metric("time_to_full", title: "Time to full", duration, "clock"))
        }
        if let odometer = snapshot.odometer {
            items.append(Metric("odometer", title: "Odometer", formattedDistance(miles: odometer, units: units), "gauge.with.needle"))
        }
        if let freshness = snapshot.freshnessMS, freshness > 0 {
            items.append(Metric("data_age", title: "Data age", formattedDuration(milliseconds: freshness), "antenna.radiowaves.left.and.right"))
        }
        if snapshot.latitude != nil, snapshot.longitude != nil {
            items.append(Metric("location", title: "Location", formattedCoordinate(latitude: snapshot.latitude, longitude: snapshot.longitude), "location"))
        }
        return items
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(metrics) { metric in
                MetricTile(title: metric.title, value: metric.value, systemImage: metric.systemImage)
            }
        }
    }
}

private struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }
}

#Preview("Control Center — Charging") {
    ZStack {
        AppScreenBackground()

        ScrollView {
            VehicleStatusCard(
                vehicleName: "Model 3",
                snapshot: PreviewData.snapshotFull,
                units: "imperial"
            )
            .padding()
        }
    }
}

#Preview("Control Center — Dark") {
    ZStack {
        AppScreenBackground()

        ScrollView {
            VehicleStatusCard(
                vehicleName: "Model 3",
                snapshot: PreviewData.snapshotFull,
                units: "imperial"
            )
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Driving") {
    ZStack {
        AppScreenBackground()

        ScrollView {
            VehicleStatusCard(
                vehicleName: "Model Y",
                snapshot: PreviewData.snapshotDriving,
                units: "imperial"
            )
            .padding()
        }
    }
}

#Preview("Metric units") {
    ZStack {
        AppScreenBackground()

        ScrollView {
            VehicleStatusCard(
                vehicleName: "Model 3",
                snapshot: PreviewData.snapshotFull,
                units: "metric"
            )
            .padding()
        }
    }
}

#Preview("No telemetry") {
    ZStack {
        AppScreenBackground()

        VehicleStatusCard(vehicleName: "Model 3", snapshot: nil, units: "imperial")
            .padding()
    }
}
