import Foundation
import WidgetKit

public struct FleetWidgetStore: Sendable {
    public static let shared = FleetWidgetStore()
    private static let cachePrefix = "fleet.widgets.snapshot."
    private static let feedbackPrefix = "fleet.widgets.feedback."
    private var appGroup: String

    public init(appGroup: String = FleetKitConfig.appGroupIdentifier) {
        self.appGroup = appGroup
    }

    public func load(
        vin: String?,
        service: FleetIntentService = .make(),
        maxCacheAge: TimeInterval = 0
    ) async throws -> FleetWidgetSnapshot {
        let mode = service.sandboxMode
        let scope = sessionScope(mode: mode)
        if maxCacheAge > 0, let recent = cached(vin: vin, mode: mode) {
            let age = Date.now.timeIntervalSince(recent.fetchedAt)
            if (0..<maxCacheAge).contains(age) {
                return recent
            }
            // If an interactive action just failed seconds ago, surface that feedback immediately
            // rather than stalling the widget on a duplicate failing network call.
            if let feedback = recent.activeFeedback(),
               feedback.outcome == .failed,
               Date.now.timeIntervalSince(feedback.timestamp) < 3 {
                return recent
            }
        }
        let vehicle = try await service.resolvedVehicle(vin)
        async let snapshot = service.snapshot(vin: vehicle.vin)
        async let units = service.units()
        var value = try await FleetWidgetSnapshot(
            vehicle: vehicle,
            snapshot: snapshot,
            usesMetric: (try? await units) == "metric",
            mode: mode
        )
        // A Start Climate tap on a sleeping car returns before the car wakes; keep showing it
        // as starting until the car reports HVAC on or the window passes.
        if let receipt = ClimateCommandReceipt.latest(vin: vehicle.vin, scope: service.sessionScopeID, group: service.appGroupIdentifier),
           receipt.isWaking, receipt.running == true {
            value.climateStartRequestedAt = receipt.date
        }
        value.actionFeedback = latestFeedback(vin: vehicle.vin, mode: mode, scope: scope)
        guard mode == service.sandboxMode, scope == sessionScope(mode: mode) else {
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

    public func recordFeedback(
        _ feedback: FleetWidgetActionFeedback,
        vin: String,
        mode: FleetSandboxMode = FleetSandboxStore.shared.mode()
    ) {
        let scope = sessionScope(mode: mode)
        let record = CachedFeedback(feedback: feedback, sessionScope: scope)
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: feedbackKey(vin: vin, mode: mode))
    }

    public func latestFeedback(
        vin: String?,
        mode: FleetSandboxMode = FleetSandboxStore.shared.mode(),
        at now: Date = .now
    ) -> FleetWidgetActionFeedback? {
        guard let resolvedVIN = resolvedVIN(vin, mode: mode) else { return nil }
        return latestFeedback(vin: resolvedVIN, mode: mode, scope: sessionScope(mode: mode), at: now)
    }

    private func latestFeedback(
        vin: String,
        mode: FleetSandboxMode,
        scope: String,
        at now: Date = .now
    ) -> FleetWidgetActionFeedback? {
        let key = feedbackKey(vin: vin, mode: mode)
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(CachedFeedback.self, from: data),
              record.sessionScope == scope else { return nil }
        guard record.feedback.isActive(at: now) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return record.feedback
    }

    public func cached(vin: String?, mode: FleetSandboxMode = FleetSandboxStore.shared.mode()) -> FleetWidgetSnapshot? {
        let scope = sessionScope(mode: mode)
        guard let resolvedVIN = resolvedVIN(vin, mode: mode),
              let data = UserDefaults(suiteName: appGroup)?.data(forKey: cacheKey(vin: resolvedVIN, mode: mode)) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedSnapshot.self, from: data),
              cached.sessionScope == scope else { return nil }
        var snapshot = cached.snapshot
        if let feedback = latestFeedback(vin: resolvedVIN, mode: mode, scope: scope) {
            snapshot.actionFeedback = feedback
        } else if snapshot.activeFeedback() == nil {
            snapshot.actionFeedback = nil
        }
        return snapshot
    }

    public func clear(reload: Bool = true) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.cachePrefix) || key.hasPrefix(Self.feedbackPrefix) {
            defaults.removeObject(forKey: key)
        }
        if reload { Self.reload() }
    }

    public static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    private func resolvedVIN(_ vin: String?, mode: FleetSandboxMode) -> String? {
        let selectedVIN = mode == .demoVehicle ? FleetDemoVehicleState.demoVIN : FleetSharedTokenStore(appGroup: appGroup).selectedVIN()
        return vin ?? selectedVIN
    }

    private func cacheKey(vin: String, mode: FleetSandboxMode) -> String {
        Self.cachePrefix + mode.rawValue + "." + vin
    }

    private func feedbackKey(vin: String, mode: FleetSandboxMode) -> String {
        Self.feedbackPrefix + mode.rawValue + "." + vin
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

    private struct CachedFeedback: Codable {
        var feedback: FleetWidgetActionFeedback
        var sessionScope: String
    }
}
