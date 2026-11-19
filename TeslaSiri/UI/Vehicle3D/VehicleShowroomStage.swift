import RealityKit
import SwiftUI

/// The live 3D car at the top of the Vehicle tab. It mirrors the real car: doors, windows
/// and trunks open as they do, the charge-port bolt pulses while charging, and the signals
/// blink when the car locks or unlocks. Parked, it sits on a showroom floor lit by its paint
/// color, with a soft shadow (and, in dark mode, a dim reflection). In gear, the scene becomes a road in the style
/// of the Full Self-Driving visualization, with lane lines streaming past at the car's speed.
struct VehicleShowroomStage: View {
    let vehicle: FleetVehicle
    let snapshot: FleetLatestSnapshot
    var activeDrive: FleetActiveDriveSession?
    var units: String?
    var stageAspectRatio: CGFloat = 1.9
    var onCommand: ((VehicleControlCommand) -> Void)?
    var onLiveRefresh: (() async -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @State private var isInViewport = true
    @State private var headingTracker = HeadingCurvatureTracker()

    private var isVisibleAndActive: Bool { isInViewport && scenePhase == .active }

    private var spec: VehicleModelSpec {
        VehicleModelSpec(configuration: snapshot.vehicleConfiguration, vin: vehicle.vin)
    }

    private var stageState: VehicleStageState {
        var state = VehicleStageState(
            snapshot: snapshot,
            activeDrive: activeDrive,
            rightHandDrive: snapshot.vehicleConfiguration?.rightHandDrive ?? false
        )
        if state.mode == .driving, state.curvature == 0 {
            state.curvature = headingTracker.curvature
        }
        return state
    }

    var body: some View {
        let state = stageState
        stageView(for: state)
        .aspectRatio(stageAspectRatio * 0.80, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if state.mode == .driving {
                VehicleDrivingReadout(speedMPH: state.speedMPH, gear: snapshot.gear, units: units, isSelfDriving: state.isSelfDriving)
                    .padding(.leading, 20)
                    .padding(.top, 4)
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: state.mode)
        .onScrollVisibilityChange(threshold: 0.01) { isInViewport = $0 }
        .onChange(of: snapshot, initial: true) { _, newValue in
            headingTracker.record(newValue)
        }
        .task(id: isVisibleAndActive && state.mode == .driving) {
            guard isVisibleAndActive, state.mode == .driving, let onLiveRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await onLiveRefresh()
            }
        }
    }

    private func stageView(for state: VehicleStageState) -> some View {
        let hotspotHandler: ((VehicleHotspot) -> Void)? = onCommand == nil ? nil : { hotspot in
            handle(hotspot)
        }
        let modelSpec = spec
        let stage = VehicleStage.shared(for: modelSpec)
        return VehicleStageView<VehicleHeroArtwork, VehicleHotspotLabel>(
            spec: modelSpec,
            state: state,
            stage: stage,
            framingZoom: 1,
            accessibilityDescription: accessibilityDescription(for: state),
            showsAmbientLight: true,
            isRendering: isVisibleAndActive,
            onHotspot: hotspotHandler,
            hotspotLabel: hotspotLabel(for:),
            placeholder: placeholderArtwork
        )
        .id(ObjectIdentifier(stage))
    }

    private func hotspotLabel(for hotspot: VehicleHotspot) -> VehicleHotspotLabel {
        VehicleHotspotLabel(hotspot: hotspot, snapshot: snapshot, isEnabled: command(for: hotspot) != nil)
    }

    private func placeholderArtwork() -> VehicleHeroArtwork {
        VehicleHeroArtwork(vehicleName: vehicle.name, vin: vehicle.vin, stageAspectRatio: stageAspectRatio)
    }

    private func command(for hotspot: VehicleHotspot) -> VehicleControlCommand? {
        guard hotspot == .chargePort ? vehicle.allowsChargingControls : vehicle.allowsVehicleControls else { return nil }
        return switch hotspot {
        case .lock:
            .lock(shouldLock: snapshot.locked != true)
        case .frunk:
            snapshot.closures?.frontTrunkOpen == true ? nil : .openFrunk
        case .trunk:
            .rearTrunk(open: snapshot.closures?.rearTrunkOpen != true)
        case .chargePort:
            snapshot.isActivelyCharging ? nil : .chargePort(open: snapshot.chargePortDoorOpen != true)
        }
    }

    private func handle(_ hotspot: VehicleHotspot) {
        guard let command = command(for: hotspot) else { return }
        onCommand?(command)
    }

    private func accessibilityDescription(for state: VehicleStageState) -> String {
        var parts = ["\(vehicle.name), 3D view"]
        switch state.mode {
        case .parked: parts.append("parked")
        case .charging: parts.append(state.isCharging ? "charging" : "plugged in")
        case .driving: parts.append("driving at \(Int(state.speedMPH.rounded())) miles per hour")
        }
        if let locked = state.isLocked { parts.append(locked ? "locked" : "unlocked") }
        let open = VehicleOpening.allCases.filter { state.openings.contains($0) }
        if !open.isEmpty {
            parts.append("open: " + open.map(\.spokenName).joined(separator: ", "))
        }
        if state.isSentryOn { parts.append("Sentry Mode on") }
        return parts.joined(separator: ", ")
    }
}

/// Chromeless Tesla-style callout floating quietly above the car with a hairline leader.
struct VehicleHotspotLabel: View {
    let hotspot: VehicleHotspot
    let snapshot: FleetLatestSnapshot
    let isEnabled: Bool

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder
    private var content: some View {
        switch hotspot {
        case .lock:
            let unlocked = snapshot.locked == false
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(unlocked ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
        case .chargePort:
            VehicleChargeBadge(snapshot: snapshot)
        case .frunk, .trunk:
            let isOpen = hotspot == .frunk
                ? snapshot.closures?.frontTrunkOpen == true
                : snapshot.closures?.rearTrunkOpen == true
            VStack(spacing: 1) {
                Text(isOpen ? (hotspot == .frunk ? "Open" : "Close") : "Open")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isOpen ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary))
                Text(hotspot == .frunk ? "Frunk" : "Trunk")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOpen ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.primary.opacity(0.88)))
            }
            .lineLimit(1)
        }
    }

    private var accessibilityTitle: String {
        switch hotspot {
        case .lock:
            snapshot.locked == false ? "Lock vehicle" : "Unlock vehicle"
        case .frunk:
            snapshot.closures?.frontTrunkOpen == true ? "Front trunk open" : "Open front trunk"
        case .trunk:
            snapshot.closures?.rearTrunkOpen == true ? "Close rear trunk" : "Open rear trunk"
        case .chargePort:
            if snapshot.isActivelyCharging, let level = snapshot.batteryLevel {
                "Charging, \(formattedNumber(level, fractionLength: 0, suffix: "%"))"
            } else {
                snapshot.chargePortDoorOpen == true ? "Close charge port" : "Open charge port"
            }
        }
    }
}

/// The charge-port callout: a disc with a bolt that is green with a soft ripple while
/// charging, blue while the port is open, and quiet gray when closed. While charging it
/// shows the battery level and the time to reach the charge limit.
struct VehicleChargeBadge: View {
    let snapshot: FleetLatestSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCharging: Bool { snapshot.isActivelyCharging }
    private var isPortOpen: Bool { snapshot.chargePortDoorOpen == true }

    var body: some View {
        HStack(spacing: 6) {
            disc

            if isCharging {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formattedNumber(snapshot.batteryLevel, fractionLength: 0, suffix: "%"))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let remaining {
                        Text(remaining)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 4)
            }
        }
        .padding(isCharging ? 4 : 0)
        .background {
            if isCharging {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().strokeBorder(AppTheme.chargeGreen.opacity(0.45), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
            }
        }
    }

    private var disc: some View {
        ZStack {
            if isCharging && !reduceMotion {
                Circle()
                    .stroke(AppTheme.chargeGreen, lineWidth: 1.5)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring
                            .scaleEffect(expanded ? 1.9 : 1)
                            .opacity(expanded ? 0 : 0.7)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.6) : .linear(duration: 0.01)
                    }
            }

            Circle()
                .fill(discFill)

            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isCharging || isPortOpen ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .frame(width: 28, height: 28)
    }

    private var discFill: AnyShapeStyle {
        if isCharging { return AnyShapeStyle(AppTheme.chargeGreen.gradient) }
        if isPortOpen { return AnyShapeStyle(AppTheme.climateBlue.gradient) }
        return AnyShapeStyle(.quaternary)
    }

    /// Hours to the charge limit, as "1h 50m".
    private var remaining: String? {
        guard let hours = snapshot.timeToFullCharge, hours > 0 else { return nil }
        let duration = Duration.seconds(hours * 3600)
        return duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// Speed and gear over the driving scene, like the instrument cluster readout.
struct VehicleDrivingReadout: View {
    let speedMPH: Double
    let gear: String?
    let units: String?
    var isSelfDriving = false

    private var isMetric: Bool { units == "metric" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(["P", "R", "N", "D"], id: \.self) { letter in
                    Text(letter)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(letter == gear?.uppercased() ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gear \(gear ?? "unknown")")

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedNumber(isMetric ? speedMPH * 1.609_344 : speedMPH, fractionLength: 0))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // Speed changes several times a second; a rolling-digit transition would
                    // overlap itself and smear, so the number just updates like a speedometer.
                Text(isMetric ? "km/h" : "mph")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if isSelfDriving {
                Label("Self-Driving", systemImage: "steeringwheel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: isSelfDriving)
    }
}

/// Estimates road curvature from successive snapshot headings when no route is available.
struct HeadingCurvatureTracker: Equatable {
    private var lastHeading: Double?
    private var lastTimestamp: Int64?
    private(set) var curvature: Double = 0

    mutating func record(_ snapshot: FleetLatestSnapshot) {
        guard let heading = snapshot.heading, let timestamp = snapshot.updatedAt ?? snapshot.timestamp else { return }
        defer {
            lastHeading = heading
            lastTimestamp = timestamp
        }
        guard let lastHeading, let lastTimestamp, timestamp > lastTimestamp else { return }
        let seconds = Double(timestamp - lastTimestamp) / 1000
        let metersPerSecond = (snapshot.speed ?? 0) * 0.44704
        guard seconds > 1, seconds < 90, metersPerSecond > 2 else {
            curvature = 0
            return
        }
        var turn = (heading - lastHeading) * .pi / 180
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        curvature = min(max(turn / (metersPerSecond * seconds), -1.0 / 12), 1.0 / 12)
    }
}

extension VehicleOpening {
    var spokenName: String {
        switch self {
        case .frunk: "front trunk"
        case .trunk: "rear trunk"
        case .chargePort: "charge port"
        case .leftFrontDoor: "left front door"
        case .rightFrontDoor: "right front door"
        case .leftRearDoor: "left rear door"
        case .rightRearDoor: "right rear door"
        case .leftFrontWindow: "left front window"
        case .rightFrontWindow: "right front window"
        case .leftRearWindow: "left rear window"
        case .rightRearWindow: "right rear window"
        }
    }
}
