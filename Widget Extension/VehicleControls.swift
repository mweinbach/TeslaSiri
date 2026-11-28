import FleetKit
import SwiftUI
import WidgetKit

// MARK: - Shared Control Value Provider

private struct VehicleControlValue: Sendable {
    var snapshot: FleetWidgetSnapshot?
    var feedback: FleetWidgetActionFeedback?

    static var preview: VehicleControlValue {
        VehicleControlValue(snapshot: .sample, feedback: nil)
    }
}

private struct VehicleControlProvider: ControlValueProvider {
    var previewValue: VehicleControlValue { .preview }

    func currentValue() async throws -> VehicleControlValue {
        let snapshot = FleetWidgetStore.shared.cached(vin: nil)
        let feedback = snapshot?.activeFeedback()
            ?? FleetWidgetStore.shared.latestFeedback(vin: nil)
        return VehicleControlValue(snapshot: snapshot, feedback: feedback)
    }
}

// MARK: - Lock Car Control

struct LockVehicleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.maxweinbach.TeslaSiri.control.lock",
            provider: VehicleControlProvider()
        ) { value in
            let feedback = value.feedback?.action == .lock ? value.feedback : nil
            let isUnlocked = value.snapshot?.locked == false

            ControlWidgetButton(action: FleetWidgetActionIntent(action: .lock)) {
                Label {
                    Text(title(for: value, feedback: feedback))
                } icon: {
                    Image(systemName: symbol(isUnlocked: isUnlocked, feedback: feedback))
                }
                .controlWidgetActionHint("Lock Car")
                .controlWidgetStatus(LocalizedStringResource(stringLiteral: status(for: value, feedback: feedback)))
            }
            .tint(tint(isUnlocked: isUnlocked, feedback: feedback))
        }
        .displayName("Lock Car")
        .description("Lock the car currently selected in Wattie.")
    }

    private func title(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?) -> String {
        if let feedback { return feedback.message }
        if value.snapshot?.locked == false {
            return String(localized: "Unlocked", comment: "Control Center button title while the car is unlocked.")
        }
        return String(localized: "Lock Car", comment: "Control Center button title for the lock action.")
    }

    private func symbol(isUnlocked: Bool, feedback: FleetWidgetActionFeedback?) -> String {
        if let feedback { return feedback.symbolName }
        return isUnlocked ? "lock.open.fill" : "lock.fill"
    }

    private func status(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?) -> String {
        if let feedback { return feedback.message }
        if let name = value.snapshot?.name {
            let lock = value.snapshot?.lockDescription
                ?? String(localized: "Lock", comment: "Control Center status when lock state is unknown.")
            return "\(name) · \(lock)"
        }
        return String(localized: "Lock Car", comment: "Control Center button title for the lock action.")
    }

    private func tint(isUnlocked: Bool, feedback: FleetWidgetActionFeedback?) -> Color {
        if let feedback {
            switch feedback.outcome {
            case .confirmed: return WidgetPalette.chargeGreen
            case .waking: return WidgetPalette.alertAmber
            case .failed: return WidgetPalette.crimson
            }
        }
        return isUnlocked ? WidgetPalette.alertAmber : WidgetPalette.climateBlue
    }
}

// MARK: - Start Climate Control

struct StartClimateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.maxweinbach.TeslaSiri.control.climate",
            provider: VehicleControlProvider()
        ) { value in
            let feedback = value.feedback?.action == .startClimate ? value.feedback : nil
            let isOn = value.snapshot?.climateOn == true
            let isWaking = value.snapshot?.isClimateStarting() == true || feedback?.outcome == .waking

            ControlWidgetButton(action: FleetWidgetActionIntent(action: .startClimate)) {
                Label {
                    Text(title(for: value, feedback: feedback, isOn: isOn, isWaking: isWaking))
                } icon: {
                    Image(systemName: symbol(feedback: feedback, isOn: isOn, isWaking: isWaking))
                }
                .controlWidgetActionHint("Start Car Climate")
                .controlWidgetStatus(LocalizedStringResource(stringLiteral: status(for: value, feedback: feedback, isOn: isOn, isWaking: isWaking)))
            }
            .tint(tint(feedback: feedback, isWaking: isWaking))
        }
        .displayName("Start Car Climate")
        .description("Precondition the car currently selected in Wattie at its existing target temperature.")
    }

    private func title(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?, isOn: Bool, isWaking: Bool) -> String {
        if let feedback { return feedback.message }
        if isWaking {
            return String(localized: "Starting…", comment: "Control Center button title while a sleeping car wakes to start climate.")
        }
        if isOn, let snapshot = value.snapshot {
            let cabin = snapshot.temperatureDescription(snapshot.insideTemperature)
            return String(localized: "On · \(cabin)", comment: "Control Center button title while cabin climate is running.")
        }
        return String(localized: "Start Climate", comment: "Control Center button title for the climate action.")
    }

    private func symbol(feedback: FleetWidgetActionFeedback?, isOn: Bool, isWaking: Bool) -> String {
        if let feedback { return feedback.symbolName }
        if isWaking { return "moon.zzz.fill" }
        return isOn ? "fan.fill" : "fan"
    }

    private func status(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?, isOn: Bool, isWaking: Bool) -> String {
        if let feedback { return feedback.message }
        if isWaking {
            return String(localized: "Waking car to start climate", comment: "Control Center status while a sleeping car wakes to start climate.")
        }
        if let snapshot = value.snapshot {
            let cabin = snapshot.temperatureDescription(snapshot.insideTemperature)
            return isOn
                ? String(localized: "Climate on · \(cabin)", comment: "Control Center status while cabin climate is running.")
                : String(localized: "Cabin \(cabin)", comment: "Control Center status showing the current cabin temperature.")
        }
        return String(localized: "Start Climate", comment: "Control Center button title for the climate action.")
    }

    private func tint(feedback: FleetWidgetActionFeedback?, isWaking: Bool) -> Color {
        if let feedback {
            switch feedback.outcome {
            case .confirmed: return WidgetPalette.chargeGreen
            case .waking: return WidgetPalette.alertAmber
            case .failed: return WidgetPalette.crimson
            }
        }
        return isWaking ? WidgetPalette.alertAmber : WidgetPalette.climateBlue
    }
}

// MARK: - Start Charging Control

struct StartChargingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.maxweinbach.TeslaSiri.control.charging",
            provider: VehicleControlProvider()
        ) { value in
            let feedback = value.feedback?.action == .startCharging ? value.feedback : nil
            let isCharging = value.snapshot?.isCharging == true

            ControlWidgetButton(action: FleetWidgetActionIntent(action: .startCharging)) {
                Label {
                    Text(title(for: value, feedback: feedback, isCharging: isCharging))
                } icon: {
                    Image(systemName: symbol(feedback: feedback, isCharging: isCharging))
                }
                .controlWidgetActionHint("Start Car Charging")
                .controlWidgetStatus(LocalizedStringResource(stringLiteral: status(for: value, feedback: feedback, isCharging: isCharging)))
            }
            .tint(tint(feedback: feedback))
        }
        .displayName("Start Car Charging")
        .description("Start charging the plugged-in car currently selected in Wattie.")
    }

    private func title(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?, isCharging: Bool) -> String {
        if let feedback { return feedback.message }
        if let snapshot = value.snapshot, let level = snapshot.batteryLevel {
            let pct = FleetKitFormatting.percent(level)
            return isCharging
                ? String(localized: "Charging · \(pct)", comment: "Control Center button title while the car is charging.")
                : String(localized: "Charge · \(pct)", comment: "Control Center button title showing battery charge.")
        }
        return String(localized: "Start Charging", comment: "Control Center button title for the charging action.")
    }

    private func symbol(feedback: FleetWidgetActionFeedback?, isCharging: Bool) -> String {
        if let feedback { return feedback.symbolName }
        return isCharging ? "bolt.batteryblock.fill" : "bolt.fill"
    }

    private func status(for value: VehicleControlValue, feedback: FleetWidgetActionFeedback?, isCharging: Bool) -> String {
        if let feedback { return feedback.message }
        if let snapshot = value.snapshot {
            if isCharging, let power = snapshot.chargerPowerKW, power > 0 {
                let watts = FleetKitFormatting.powerKW(power, fractionLength: 1)
                return String(localized: "Charging at \(watts)", comment: "Control Center status showing charger power.")
            }
            return snapshot.chargingDescription
        }
        return String(localized: "Start Charging", comment: "Control Center button title for the charging action.")
    }

    private func tint(feedback: FleetWidgetActionFeedback?) -> Color {
        if let feedback {
            switch feedback.outcome {
            case .confirmed: return WidgetPalette.chargeGreen
            case .waking: return WidgetPalette.alertAmber
            case .failed: return WidgetPalette.crimson
            }
        }
        return WidgetPalette.chargeGreen
    }
}
