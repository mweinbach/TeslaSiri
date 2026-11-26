import AppIntents
import FleetKit
import SwiftUI

enum VehicleControlCommand: Hashable, Identifiable {
    case charge(shouldStart: Bool)
    case chargePort(open: Bool)
    case climate(shouldTurnOn: Bool)
    case defrost(shouldTurnOn: Bool)
    case flashLights
    case honk
    case lock(shouldLock: Bool)
    case petMode(shouldTurnOn: Bool)
    case openFrunk
    case rearTrunk(open: Bool)
    case sentryMode(shouldTurnOn: Bool)
    case setCabinTemperature(celsius: Double)
    case setChargeLimit(percent: Int)
    case ventWindows

    var id: String {
        switch self {
        case .charge(let shouldStart): "charge-\(shouldStart)"
        case .chargePort(let open): "charge-port-\(open)"
        case .climate(let shouldTurnOn): "climate-\(shouldTurnOn)"
        case .defrost(let shouldTurnOn): "defrost-\(shouldTurnOn)"
        case .flashLights: "flash-lights"
        case .honk: "honk"
        case .lock(let shouldLock): "lock-\(shouldLock)"
        case .petMode(let shouldTurnOn): "pet-mode-\(shouldTurnOn)"
        case .openFrunk: "front-trunk"
        case .rearTrunk(let open): open ? "open-rear-trunk" : "close-rear-trunk"
        case .sentryMode(let shouldTurnOn): "sentry-\(shouldTurnOn)"
        case .setCabinTemperature(let celsius): "set-temp-\(Int((celsius * 10).rounded()))"
        case .setChargeLimit(let percent): "charge-limit-\(percent)"
        case .ventWindows: "vent-windows"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .charge(let shouldStart): shouldStart ? "Start charging" : "Stop charging"
        case .chargePort(let open): open ? "Open charge port" : "Close charge port"
        case .climate(let shouldTurnOn): shouldTurnOn ? "Start climate" : "Stop climate"
        case .defrost(let shouldTurnOn): shouldTurnOn ? "Start defrost" : "Stop defrost"
        case .flashLights: "Flash lights"
        case .honk: "Honk horn"
        case .lock(let shouldLock): shouldLock ? "Lock vehicle" : "Unlock vehicle"
        case .petMode(let shouldTurnOn): shouldTurnOn ? "Turn on Dog Mode" : "Turn off Dog Mode"
        case .openFrunk: "Open front trunk"
        case .rearTrunk(let open): open ? "Open rear trunk" : "Close rear trunk"
        case .sentryMode(let shouldTurnOn): shouldTurnOn ? "Turn on Sentry Mode" : "Turn off Sentry Mode"
        case .setCabinTemperature: "Set cabin temperature"
        case .setChargeLimit(let percent): "Set charge limit to \(percent)%"
        case .ventWindows: "Vent windows"
        }
    }

    func conflicts(with other: Self) -> Bool {
        switch (self, other) {
        case (.charge, .charge),
             (.climate, .climate),
             (.lock, .lock),
             (.chargePort, .chargePort),
             (.rearTrunk, .rearTrunk),
             (.sentryMode, .sentryMode),
             (.setChargeLimit, .setChargeLimit),
             (.setCabinTemperature, .setCabinTemperature):
            true
        default:
            self == other
        }
    }

    func observedState(in snapshot: FleetLatestSnapshot?) -> Bool? {
        switch self {
        case .charge: snapshot?.isActivelyCharging
        case .climate: snapshot?.climateOn
        case .lock: snapshot?.locked
        case .chargePort: snapshot?.chargePortDoorOpen
        case .openFrunk: snapshot?.closures?.frontTrunkOpen
        case .rearTrunk: snapshot?.closures?.rearTrunkOpen
        case .sentryMode: snapshot?.sentryMode
        default: nil
        }
    }

    var expectedState: Bool? {
        switch self {
        case .charge(let on), .climate(let on), .lock(let on), .chargePort(let on), .sentryMode(let on): on
        case .openFrunk: true
        case .rearTrunk(let open): open
        default: nil
        }
    }

    var action: String {
        switch self {
        case .charge(let shouldStart): shouldStart ? "charge_start" : "charge_stop"
        case .climate(let shouldTurnOn):
            shouldTurnOn ? "auto_conditioning_start" : "auto_conditioning_stop"
        case .chargePort(let open): open ? "charge_port_door_open" : "charge_port_door_close"
        case .defrost: "remote_defrost"
        case .flashLights: "flash_lights"
        case .honk: "honk_horn"
        case .lock(let shouldLock): shouldLock ? "door_lock" : "door_unlock"
        case .petMode: "set_pet_mode"
        case .openFrunk, .rearTrunk: "actuate_trunk"
        case .sentryMode: "set_sentry_mode"
        case .setCabinTemperature: "set_temps"
        case .setChargeLimit: "set_charge_limit"
        case .ventWindows: "window_control"
        }
    }

    var parameters: [String: JSONValue] {
        switch self {
        case .defrost(let shouldTurnOn):
            ["on": .bool(shouldTurnOn)]
        case .petMode(let shouldTurnOn):
            ["on": .bool(shouldTurnOn)]
        case .openFrunk: ["which_trunk": "front"]
        case .rearTrunk(let open): ["which_trunk": "rear", "command": .string(open ? "open" : "close")]
        case .sentryMode(let shouldTurnOn):
            ["on": .bool(shouldTurnOn)]
        case .setCabinTemperature(let celsius):
            ["driver_temp": .double(celsius), "passenger_temp": .double(celsius)]
        case .setChargeLimit(let percent):
            ["percent": .integer(percent)]
        case .ventWindows:
            ["command": .string("vent")]
        default:
            [:]
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .lock(shouldLock: false),
             .openFrunk,
             .rearTrunk,
             .chargePort(open: true),
             .charge(shouldStart: false),
             .setChargeLimit,
             .sentryMode(shouldTurnOn: false):
            true
        case .charge(shouldStart: true),
             .chargePort(open: false),
             .climate,
             .defrost,
             .flashLights,
             .honk,
             .lock(shouldLock: true),
             .petMode,
             .sentryMode(shouldTurnOn: true),
             .setCabinTemperature,
             .ventWindows:
            false
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        case .lock(shouldLock: false), .charge(shouldStart: false), .sentryMode(shouldTurnOn: false):
            .destructive
        default:
            nil
        }
    }

    func confirmationMessage(vehicleName: String) -> LocalizedStringResource {
        switch self {
        case .lock(shouldLock: false):
            "Unlock \(vehicleName)?"
        case .openFrunk:
            "Open the front trunk on \(vehicleName)?"
        case .rearTrunk(let open):
            open ? "Open the rear trunk on \(vehicleName)?" : "Close the rear trunk on \(vehicleName)?"
        case .chargePort(let open):
            open
                ? "Open the charge port on \(vehicleName)?"
                : "Close the charge port on \(vehicleName)?"
        case .charge(shouldStart: false):
            "Stop charging \(vehicleName)?"
        case .setChargeLimit(let percent):
            "Set the charge limit on \(vehicleName) to \(percent)%?"
        case .sentryMode(shouldTurnOn: false):
            "Turn off Sentry Mode on \(vehicleName)?"
        default:
            "Send this command to \(vehicleName)?"
        }
    }
}
extension FleetVehicle {
    func allows(_ command: VehicleControlCommand) -> Bool {
        switch command {
        case .charge, .chargePort, .setChargeLimit:
            return allowsChargingControls
        default:
            return allowsVehicleControls
        }
    }
}

struct VehicleControlDashboard: View {
    let vehicle: FleetVehicle
    let vehicles: [FleetVehicle]
    let selectedVIN: String?
    let units: String?
    let isRefreshing: Bool
    let isRunningControl: Bool
    let activeControlAction: String?
    let controlMessage: String?
    let controlsEnabled: Bool
    let onSelectVehicle: (String) -> Void
    let onRefresh: () async -> Void
    let onControl: (String, [String: JSONValue]) async -> Bool

    @Environment(\.duoPosture) private var duoPosture
    @State private var pendingCommand: VehicleControlCommand?
    @State private var isShowingConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            VehicleHeroStage(
                vehicle: vehicle,
                units: units,
                compact: duoPosture.prefersCompactHero,
                onCommand: request,
                onLiveRefresh: onRefresh
            )

            if let snapshot = vehicle.latest {
                VehicleQuickActionBar(
                    snapshot: snapshot,
                    units: units,
                    isRunningControl: isRunningControl,
                    activeControlAction: activeControlAction,
                    controlMessage: controlMessage,
                    controlsEnabled: controlsEnabled,
                    onCommand: request
                )
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .appEntityIdentifier(statusEntityIdentifier)
        .vehicleCommandConfirmation(
            vehicleName: vehicle.name,
            pendingCommand: $pendingCommand,
            isPresented: $isShowingConfirmation,
            onConfirm: perform
        )
    }

    private var statusEntityIdentifier: EntityIdentifier? {
        guard let vin = vehicle.latest?.vin, !vin.isEmpty else { return nil }
        return EntityIdentifier(
            for: VehicleStatusEntity.self,
            identifier: VehicleStatusEntity.entityID(forVIN: vin)
        )
    }

    private func request(_ command: VehicleControlCommand) {
        guard controlsEnabled, !isRunningControl else { return }
        if command.requiresConfirmation {
            pendingCommand = command
            isShowingConfirmation = true
        } else {
            perform(command)
        }
    }

    private func perform(_ command: VehicleControlCommand) {
        pendingCommand = nil
        Task {
            _ = await onControl(command.action, command.parameters)
        }
    }
}

/// Showroom stage at the top of the Vehicle tab: the car render edge to edge, with the
/// three headline numbers (range, battery, cabin) resting on its reflection floor.
struct VehicleHeroStage: View {
    let vehicle: FleetVehicle
    let units: String?
    var compact: Bool = false
    var activeDrive: FleetActiveDriveSession?
    var onCommand: ((VehicleControlCommand) -> Void)?
    var onLiveRefresh: (() async -> Void)?

    var body: some View {
        if let snapshot = vehicle.latest {
            VStack(spacing: 0) {
                VehicleShowroomStage(
                    vehicle: vehicle,
                    snapshot: snapshot,
                    activeDrive: activeDrive,
                    units: units,
                    stageAspectRatio: compact ? 2.15 : 1.9,
                    onCommand: onCommand,
                    onLiveRefresh: onLiveRefresh
                )

                VehicleHeroStats(snapshot: snapshot, units: units, compact: compact)
                    .padding(.horizontal, 16)
                    .padding(.top, compact ? -2 : -6)
            }
            .frame(maxWidth: .infinity)
            .appEntityIdentifier(vehicleEntityIdentifier)
        } else {
            VehicleUnavailableStage(vehicleName: vehicle.name, compact: compact)
                .appEntityIdentifier(vehicleEntityIdentifier)
        }
    }

    private var vehicleEntityIdentifier: EntityIdentifier? {
        guard !vehicle.vin.isEmpty else { return nil }
        return EntityIdentifier(for: VehicleEntity.self, identifier: vehicle.vin)
    }
}

/// Range, battery, and cabin temperature as three large rounded numerals.
private struct VehicleHeroStats: View {
    let snapshot: FleetLatestSnapshot
    let units: String?
    var compact: Bool = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 0) {
                rangeStat
                separator
                batteryStat
                if snapshot.insideTemp != nil {
                    separator
                    cabinStat
                }
            }

            VStack(spacing: 12) {
                rangeStat
                batteryStat
                if snapshot.insideTemp != nil {
                    cabinStat
                }
            }
        }
        .appEntityIdentifier(statusEntityIdentifier)
    }

    private var valueFont: Font {
        .system(compact ? .title : .largeTitle, design: .rounded, weight: .semibold)
    }

    private var rangeStat: some View {
        stat(
            value: rangeValue,
            unit: rangeUnit,
            caption: Text("Range"),
            accessibilityLabel: "Estimated range",
            accessibilityValue: formattedDistance(miles: snapshot.batteryRange, units: units)
        )
    }

    private var batteryStat: some View {
        stat(
            value: formattedNumber(snapshot.batteryLevel, fractionLength: 0),
            unit: "%",
            valueTint: snapshot.isActivelyCharging ? AppTheme.chargeGreen : .primary,
            caption: snapshot.isActivelyCharging
                ? Text("\(Image(systemName: "bolt.fill")) Charging").foregroundStyle(AppTheme.chargeGreen)
                : Text("Battery"),
            accessibilityLabel: snapshot.isActivelyCharging ? "Battery, charging" : "Battery",
            accessibilityValue: formattedPercent(snapshot.batteryLevel)
        )
    }

    private var cabinStat: some View {
        stat(
            value: formattedNumber(snapshot.insideTemp, fractionLength: 0, suffix: "°"),
            unit: nil,
            valueTint: snapshot.climateOn == true ? AppTheme.climateBlue : .primary,
            caption: snapshot.climateOn == true
                ? Text("Climate On").foregroundStyle(AppTheme.climateBlue)
                : Text("Inside"),
            accessibilityLabel: snapshot.climateOn == true ? "Cabin temperature, climate on" : "Cabin temperature",
            accessibilityValue: formattedTemperature(snapshot.insideTemp, inFahrenheit: !prefersMetricUnits(units))
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: compact ? 26 : 34)
            .accessibilityHidden(true)
    }

    private func stat(
        value: String,
        unit: String?,
        valueTint: Color = .primary,
        caption: Text,
        accessibilityLabel: LocalizedStringKey,
        accessibilityValue: String
    ) -> some View {
        VStack(spacing: 3) {
            MetricValueText(
                value: value,
                unit: unit,
                font: valueFont,
                unitFont: compact ? .subheadline.weight(.semibold) : .headline
            )
            .foregroundStyle(valueTint)
            caption
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var rangeValue: String {
        guard let batteryRange = snapshot.batteryRange else { return "--" }
        let value = prefersMetricUnits(units) ? batteryRange * 1.609_344 : batteryRange
        return formattedNumber(value, fractionLength: 0)
    }

    private var rangeUnit: String {
        prefersMetricUnits(units) ? UnitLength.kilometers.symbol : UnitLength.miles.symbol
    }

    private var statusEntityIdentifier: EntityIdentifier? {
        guard !snapshot.vin.isEmpty else { return nil }
        return EntityIdentifier(
            for: VehicleStatusEntity.self,
            identifier: VehicleStatusEntity.entityID(forVIN: snapshot.vin)
        )
    }
}

/// Labeled Liquid Glass quick controls (Lock, Climate, Frunk, Trunk, More).
/// Controls whose state is "active" (unlocked, climate on, trunk open) switch to the
/// prominent glass style so the car's state reads at a glance.
struct VehicleQuickActionBar: View {
    let snapshot: FleetLatestSnapshot
    let units: String?
    let isRunningControl: Bool
    let activeControlAction: String?
    var pendingControls: Set<VehicleControlCommand> = []
    let controlMessage: String?
    var controlMessageIsError: Bool = false
    var isWaking: Bool = false
    var isRefreshing: Bool = false
    let controlsEnabled: Bool
    let onCommand: (VehicleControlCommand) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hapticTrigger = 0

    private var isLocked: Bool { snapshot.locked == true }
    private var isClimateOn: Bool { snapshot.climateOn == true }
    private var isFrunkOpen: Bool { snapshot.closures?.frontTrunkOpen == true }
    private var isTrunkOpen: Bool { snapshot.closures?.rearTrunkOpen == true }
    private var isSentryOn: Bool { snapshot.sentryMode == true }

    var body: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        controls
                    }
                } else {
                    HStack(spacing: 8) {
                        controls
                    }
                }
            }
            .disabled(!controlsEnabled || isRunningControl)
            .sensoryFeedback(.impact(flexibility: .solid), trigger: hapticTrigger)

            if isWaking {
                VehicleControlStatusLine(message: LocalizedStringKey("Waking vehicle…"), isRunning: true, isError: false)
            } else if let controlMessage {
                VehicleControlStatusLine(
                    message: controlMessage,
                    isRunning: isRunningControl || !pendingControls.isEmpty,
                    isError: controlMessageIsError
                )
            } else if isRefreshing {
                VehicleControlStatusLine(message: LocalizedStringKey("Refreshing vehicle data…"), isRunning: true, isError: false)
            } else if let updatedAt = snapshot.updatedAtDate {
                RelativeTimeText(date: updatedAt, style: .updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: isWaking)
        .animation(.smooth(duration: 0.25), value: controlMessage)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        quickAction(
            title: isLocked ? "Locked" : "Unlocked",
            systemImage: isLocked ? "lock.fill" : "lock.open.fill",
            command: .lock(shouldLock: !isLocked),
            isActive: !isLocked,
            tint: AppTheme.alertAmber,
            accessibilityLabel: isLocked ? "Unlock vehicle" : "Lock vehicle",
            accessibilityValue: isLocked
                ? String(localized: "Locked", comment: "Accessibility value when vehicle is locked")
                : String(localized: "Unlocked", comment: "Accessibility value when vehicle is unlocked")
        )

        quickAction(
            title: "Climate",
            systemImage: isClimateOn ? "fan.fill" : "fan",
            command: .climate(shouldTurnOn: !isClimateOn),
            isActive: isClimateOn,
            tint: AppTheme.climateBlue,
            rotates: isClimateOn && !reduceMotion,
            accessibilityLabel: isClimateOn ? "Stop climate" : "Start climate",
            accessibilityValue: climateAccessibilityValue
        )

        quickAction(
            title: Text(LocalizedStringResource("quickAction.frunk", defaultValue: "Frunk", comment: "Short quick-action tile label for front trunk")),
            systemImage: "car.side.front.open",
            command: .openFrunk,
            isActive: isFrunkOpen,
            tint: AppTheme.alertAmber,
            accessibilityLabel: isFrunkOpen ? "Front trunk" : "Open front trunk",
            accessibilityValue: isFrunkOpen
                ? String(localized: "Open", comment: "Accessibility value when a trunk or compartment is open")
                : String(localized: "Closed", comment: "Accessibility value when a trunk or compartment is closed")
        )

        quickAction(
            title: "Trunk",
            systemImage: "car.side.rear.open",
            command: .rearTrunk(open: !isTrunkOpen),
            isActive: isTrunkOpen,
            tint: AppTheme.alertAmber,
            accessibilityLabel: isTrunkOpen ? "Close rear trunk" : "Open rear trunk",
            accessibilityValue: isTrunkOpen
                ? String(localized: "Open", comment: "Accessibility value when a trunk or compartment is open")
                : String(localized: "Closed", comment: "Accessibility value when a trunk or compartment is closed")
        )

        moreMenu
    }

    private func quickAction(
        title: LocalizedStringKey,
        systemImage: String,
        command: VehicleControlCommand,
        isActive: Bool,
        tint: Color,
        rotates: Bool = false,
        accessibilityLabel: LocalizedStringKey,
        accessibilityValue: String
    ) -> some View {
        quickAction(
            title: Text(title),
            systemImage: systemImage,
            command: command,
            isActive: isActive,
            tint: tint,
            rotates: rotates,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue
        )
    }

    private func quickAction(
        title: Text,
        systemImage: String,
        command: VehicleControlCommand,
        isActive: Bool,
        tint: Color,
        rotates: Bool = false,
        accessibilityLabel: LocalizedStringKey,
        accessibilityValue: String
    ) -> some View {
        Button {
            trigger(command)
        } label: {
            QuickActionLabel(
                titleText: title,
                systemImage: systemImage,
                isBusy: isBusy(command),
                rotates: rotates
            )
        }
        .buttonStyle(QuickActionButtonStyle(isActive: isActive, tint: tint))
        .disabled(isBusy(command))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var moreMenu: some View {
        Menu {
            Section("Cabin") {
                Button("Defrost", systemImage: "windshield.front.and.heat.waves") {
                    trigger(.defrost(shouldTurnOn: true))
                }
                Button("Dog Mode", systemImage: "pawprint.fill") {
                    trigger(.petMode(shouldTurnOn: true))
                }
                Button("Vent Windows", systemImage: "car.window.right") {
                    trigger(.ventWindows)
                }
                if isClimateOn {
                    Button("Turn Off Climate", systemImage: "fan.slash") {
                        trigger(.climate(shouldTurnOn: false))
                    }
                    .disabled(isBusy(.climate(shouldTurnOn: false)))
                }
            }

            Section("Security & Alerts") {
                if isSentryOn {
                    Button("Turn Off Sentry Mode", systemImage: "eye.slash") {
                        trigger(.sentryMode(shouldTurnOn: false))
                    }
                } else {
                    Button("Turn On Sentry Mode", systemImage: "eye.fill") {
                        trigger(.sentryMode(shouldTurnOn: true))
                    }
                }
                Button("Flash Lights", systemImage: "light.max") {
                    trigger(.flashLights)
                }
                Button("Honk Horn", systemImage: "horn.blast.fill") {
                    trigger(.honk)
                }
            }
        } label: {
            QuickActionLabel(title: "More", systemImage: "ellipsis")
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: QuickActionButtonStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More vehicle controls")
    }

    private var climateAccessibilityValue: String {
        let cabin = formattedTemperature(snapshot.insideTemp, inFahrenheit: !prefersMetricUnits(units))
        if isClimateOn {
            return String(localized: "On, cabin \(cabin)", comment: "VoiceOver value when climate is on with cabin temperature")
        }
        return String(localized: "Off, cabin \(cabin)", comment: "VoiceOver value when climate is off with cabin temperature")
    }

    private func isBusy(_ command: VehicleControlCommand) -> Bool {
        (isRunningControl && activeControlAction == command.action) || pendingControls.contains { $0.conflicts(with: command) }
    }

    private func trigger(_ command: VehicleControlCommand) {
        hapticTrigger += 1
        onCommand(command)
    }
}

private struct QuickActionLabel: View {
    let titleText: Text
    let systemImage: String
    var isBusy: Bool = false
    var rotates: Bool = false

    init(titleText: Text, systemImage: String, isBusy: Bool = false, rotates: Bool = false) {
        self.titleText = titleText
        self.systemImage = systemImage
        self.isBusy = isBusy
        self.rotates = rotates
    }

    init(title: LocalizedStringKey, systemImage: String, isBusy: Bool = false, rotates: Bool = false) {
        self.titleText = Text(title)
        self.systemImage = systemImage
        self.isBusy = isBusy
        self.rotates = rotates
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .medium))
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: rotates)
                }
            }
            .frame(height: 24)

            titleText
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(.rect(cornerRadius: QuickActionButtonStyle.cornerRadius))
    }
}

/// Liquid Glass tile for quick controls. Active controls get a tinted glass fill.
private struct QuickActionButtonStyle: ButtonStyle {
    static let cornerRadius: CGFloat = 18

    let isActive: Bool
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .glassEffect(
                isActive ? .regular.tint(tint).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: Self.cornerRadius, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.55)
    }
}

extension View {
    func vehicleCommandConfirmation(
        vehicleName: String,
        pendingCommand: Binding<VehicleControlCommand?>,
        isPresented: Binding<Bool>,
        onConfirm: @escaping (VehicleControlCommand) -> Void
    ) -> some View {
        confirmationDialog(
            "Confirm vehicle command",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            if let command = pendingCommand.wrappedValue {
                Button(role: command.buttonRole) {
                    onConfirm(command)
                } label: {
                    Text(command.title)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let command = pendingCommand.wrappedValue {
                Text(command.confirmationMessage(vehicleName: vehicleName))
            }
        }
    }
}

extension FleetLatestSnapshot {
    var isActivelyCharging: Bool {
        chargingState?.localizedCaseInsensitiveContains("charging") == true
    }

    /// One-line driving/charging + lock summary shown as the navigation subtitle.
    var heroStatusLine: String {
        heroStatusLine(units: nil)
    }

    func heroStatusLine(units: String?) -> String {
        var parts: [String] = []
        if isActivelyCharging {
            if let power = chargerPowerKW, power > 0 {
                let powerText = formattedPowerKW(power)
                parts.append(String(localized: "Charging at \(powerText)", comment: "Vehicle subtitle when actively charging with power"))
            } else {
                parts.append(String(localized: "Charging", comment: "Vehicle subtitle when actively charging"))
            }
        } else if let speed, speed > 0 {
            let speedText = formattedSpeed(mph: speed, units: units)
            parts.append(String(localized: "Driving \(speedText)", comment: "Vehicle subtitle when driving with current speed"))
        } else if let gear, !gear.isEmpty, gear != "P" {
            parts.append(String(localized: "In \(gear)", comment: "Vehicle subtitle showing current shift gear"))
        } else {
            parts.append(String(localized: "Parked", comment: "Vehicle subtitle when parked"))
        }
        if let locked {
            parts.append(
                locked
                    ? String(localized: "Locked", comment: "Vehicle subtitle lock state: locked")
                    : String(localized: "Unlocked", comment: "Vehicle subtitle lock state: unlocked")
            )
        }
        if sentryMode == true {
            parts.append(String(localized: "Sentry On", comment: "Vehicle subtitle when Sentry Mode is active"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct VehicleControlStatusLine: View {
    let message: Text
    let isRunning: Bool
    var isError: Bool = false

    init(message: LocalizedStringKey, isRunning: Bool, isError: Bool = false) {
        self.message = Text(message)
        self.isRunning = isRunning
        self.isError = isError
    }

    @_disfavoredOverload
    init<S: StringProtocol>(message: S, isRunning: Bool, isError: Bool = false) {
        self.message = Text(message)
        self.isRunning = isRunning
        self.isError = isError
    }

    var body: some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.alertAmber)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.chargeGreen)
                    .accessibilityHidden(true)
            }
            message
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(isError ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            (isError ? AppTheme.alertAmber.opacity(0.12) : AppTheme.insetSurface),
            in: Capsule()
        )
    }
}

private struct VehicleUnavailableStage: View {
    let vehicleName: String
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            VehicleHeroArtwork(vehicleName: vehicleName, vin: "", stageAspectRatio: compact ? 2.15 : 1.9)
                .opacity(0.6)

            Label("Waiting for \(vehicleName) to report in…", systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

extension FleetVehicleConfiguration {
    var displaySpecLine: String? {
        let parts = [
            humanizedModelName,
            humanizedTrimName,
            humanizedPaintName
        ].compactMap { $0 }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    var humanizedModelName: String? {
        carType.flatMap(Self.humanizedModel)
    }

    var humanizedTrimName: String? {
        trimBadging.flatMap(Self.humanizedTrim)
    }

    var humanizedPaintName: String? {
        if let override = paintColorOverride.flatMap(Self.humanizedCamelCase) {
            return override
        }
        return exteriorColor.flatMap(Self.humanizedCamelCase)
    }

    var humanizedWheelName: String? {
        wheelType.flatMap(Self.humanizedWheel)
    }

    private static func humanizedWheel(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        if lowered.hasPrefix("arachnid") {
            return cleaned.hasSuffix("21") ? "21\" Arachnid" : "Arachnid"
        }
        if lowered.hasPrefix("uberturbine") {
            if cleaned.hasSuffix("21") { return "21\" Überturbine" }
            if cleaned.hasSuffix("20") { return "20\" Überturbine" }
            return "Überturbine"
        }
        if lowered.hasPrefix("pinwheel") {
            return "18\" Aero"
        }
        if lowered.hasPrefix("photon") {
            return "18\" Photon"
        }
        if lowered.hasPrefix("nova") {
            return "19\" Nova"
        }
        if lowered.hasPrefix("gemini") {
            return "19\" Gemini"
        }
        if lowered.hasPrefix("induction") {
            return "20\" Induction"
        }
        if lowered.hasPrefix("tempest") {
            return "19\" Tempest"
        }
        if lowered.hasPrefix("stiletto") {
            return "19\" Sport"
        }
        return humanizedCamelCase(cleaned)
    }

    private static func humanizedModel(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "model3": "Model 3"
        case "modely": "Model Y"
        case "models", "models2": "Model S"
        case "modelx": "Model X"
        case "cybertruck": "Cybertruck"
        default: humanizedCamelCase(raw)
        }
    }

    private static func humanizedTrim(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        switch cleaned.lowercased() {
        case "long_range", "lr", "74d", "75d", "100d":
            return "Long Range"
        case "performance", "p74d", "p100d":
            return "Performance"
        case "plaid":
            return "Plaid"
        case "standard", "sr", "50", "60":
            return "Rear-Wheel Drive"
        default:
            return humanizedStatus(cleaned)
        }
    }

    fileprivate static func humanizedCamelCase(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("_") {
            return humanizedStatus(trimmed)
        }
        var result = ""
        for character in trimmed {
            if let last = result.last,
               (character.isUppercase && last.isLowercase) || (character.isNumber && !last.isNumber) {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }
}
