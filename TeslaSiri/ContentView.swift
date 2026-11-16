import AppIntents
import FleetKit
import SwiftUI

@main
struct TeslaSiriApp: App {
    @State private var store = FleetBackend.makeDataStore(provider: FleetSharedTokenStore.shared.provider)
    @State private var isSwitchingProvider = false

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
            let current = store
            FleetWindow(
                store: current,
                isCurrentSession: { store === current && !isSwitchingProvider },
                onSelectProvider: { provider in
                    Task { await selectProvider(provider) }
                }
            )
            .disabled(isSwitchingProvider)
            .task { await BatteryReminderManager.shared.prepare() }
        }
    }

    private func selectProvider(_ provider: FleetProvider) async {
        guard provider != store.provider, !isSwitchingProvider else { return }
        isSwitchingProvider = true
        defer { isSwitchingProvider = false }

        let outgoingVehicles = store.vehicles
        FleetSharedTokenStore.shared.selectProvider(provider)
        await store.reset(clearCache: false)
        await FleetTokenBridge.clearVehicleSystemData(for: outgoingVehicles)
        store = FleetBackend.makeDataStore(provider: provider)
    }
}

private struct FleetWindow: View {
    let store: FleetDataStore
    let isCurrentSession: () -> Bool
    let onSelectProvider: (FleetProvider) -> Void

    @State private var selectedTab: AppTab = CommandLine.arguments.contains("--verify-demo-siri") ? .diagnostics : .dashboard

    var body: some View {
        AppRootView(
            store: store,
            tokenStore: FleetBackend.makeAccessTokenStore(provider: store.provider),
            selectedTab: $selectedTab,
            isCurrentSession: isCurrentSession,
            onSelectProvider: onSelectProvider
        )
        .id(ObjectIdentifier(store))
    }
}

extension TeslaSiriApp: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FleetKitPackage.self]
    }
}
