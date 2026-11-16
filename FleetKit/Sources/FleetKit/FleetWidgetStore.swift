import Foundation
import WidgetKit

public struct FleetWidgetStore: Sendable {
    public static let shared = FleetWidgetStore()
    private static let cachePrefix = "fleet.widgets.snapshot."
    private var appGroup: String

    public init(appGroup: String = FleetKitConfig.appGroupIdentifier) {
        self.appGroup = appGroup
    }

    public func load(vin: String?, service: FleetIntentService = .make()) async throws -> FleetWidgetSnapshot {
        let mode = FleetSandboxStore.shared.mode()
        let scope = sessionScope(mode: mode)
        let vehicle = try await service.resolvedVehicle(vin)
        async let snapshot = service.snapshot(vin: vehicle.vin)
        async let units = service.units()
        let value = try await FleetWidgetSnapshot(
            vehicle: vehicle,
            snapshot: snapshot,
            usesMetric: (try? await units) == "metric",
            mode: mode
        )
        guard mode == FleetSandboxStore.shared.mode(), scope == sessionScope(mode: mode) else {
            throw CancellationError()
        }
        save(value, scope: scope)
        return value
    }

    public func save(_ snapshot: FleetWidgetSnapshot) {
        save(snapshot, scope: sessionScope(mode: snapshot.mode))
    }

    private func save(_ snapshot: FleetWidgetSnapshot, scope: String) {
        let cached = CachedSnapshot(snapshot: snapshot, sessionScope: scope)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: cacheKey(vin: snapshot.vin, mode: snapshot.mode))
    }

    public func cached(vin: String?, mode: FleetSandboxMode = FleetSandboxStore.shared.mode()) -> FleetWidgetSnapshot? {
        let selectedVIN = mode == .demoVehicle ? FleetDemoVehicleState.demoVIN : FleetSharedTokenStore(appGroup: appGroup).selectedVIN()
        guard let vin = vin ?? selectedVIN,
              let data = UserDefaults(suiteName: appGroup)?.data(forKey: cacheKey(vin: vin, mode: mode)) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedSnapshot.self, from: data),
              cached.sessionScope == sessionScope(mode: mode) else { return nil }
        return cached.snapshot
    }

    public func clear(reload: Bool = true) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.cachePrefix) {
            defaults.removeObject(forKey: key)
        }
        if reload { Self.reload() }
    }

    public static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    private func cacheKey(vin: String, mode: FleetSandboxMode) -> String {
        Self.cachePrefix + mode.rawValue + "." + vin
    }

    private func sessionScope(mode: FleetSandboxMode) -> String {
        if mode == .demoVehicle { return mode.rawValue }
        let tokens = FleetSharedTokenStore(appGroup: appGroup)
        return tokens.accessToken().map { tokens.sessionScope(fingerprint: FleetSharedTokenStore.fingerprint(for: $0)) } ?? "signed-out"
    }

    private struct CachedSnapshot: Codable {
        var snapshot: FleetWidgetSnapshot
        var sessionScope: String
    }
}
