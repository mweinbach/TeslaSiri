import FleetKit
import SwiftUI
import WidgetKit

struct LockVehicleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.maxweinbach.TeslaSiri.control.lock") {
            ControlWidgetButton(action: FleetWidgetActionIntent(action: .lock)) {
                Label("Lock Car", systemImage: "lock.fill")
            }
        }
        .displayName("Lock Car")
        .description("Lock the car currently selected in Wattie.")
    }
}

struct StartClimateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.maxweinbach.TeslaSiri.control.climate") {
            ControlWidgetButton(action: FleetWidgetActionIntent(action: .startClimate)) {
                Label("Start Climate", systemImage: "fan.fill")
            }
        }
        .displayName("Start Car Climate")
        .description("Precondition the car currently selected in Wattie at its existing target temperature.")
    }
}

struct StartChargingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.maxweinbach.TeslaSiri.control.charging") {
            ControlWidgetButton(action: FleetWidgetActionIntent(action: .startCharging)) {
                Label("Start Charging", systemImage: "bolt.fill")
            }
        }
        .displayName("Start Car Charging")
        .description("Start charging the plugged-in car currently selected in Wattie.")
    }
}
