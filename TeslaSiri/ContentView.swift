import AppIntents
import FleetKit
import SwiftUI

@main
struct TeslaSiriApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = FleetBackend.makeDataStore()
    @State private var tokenStore = FleetBackend.makeAccessTokenStore()

    init() {
        BatteryReminderManager.shared.registerBackgroundTask()
        if CommandLine.arguments.contains("--verify-demo-siri") {
            FleetSandboxStore.shared.setMode(.demoVehicle)
            Task { @MainActor in
                await DemoSiriVerificationRunner.shared.runAllOnDemoCar()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                store: store,
                tokenStore: tokenStore
            )
            .task {
                await FleetTokenBridge.sync(store: store)
                await BatteryReminderManager.shared.prepare()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await FleetTokenBridge.sync(store: store)
                }
            }
        }
    }
}

extension TeslaSiriApp: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FleetKitPackage.self]
    }
}
