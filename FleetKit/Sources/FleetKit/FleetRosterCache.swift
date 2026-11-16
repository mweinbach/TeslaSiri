import Foundation

/// A short-lived authenticated roster, shared by Siri's lookup and execution phases.
actor FleetRosterCache {
    struct Roster: Sendable {
        var vehicles: [FleetVehicleInfo]
        let units: String?

        mutating func invalidate(vin: String, topics: Set<ChangedTelemetry>) {
            guard let index = vehicles.firstIndex(where: { $0.vin == vin }) else { return }
            vehicles[index] = vehicles[index].afterCommand(
                invalidatingCharge: topics.contains(.charge),
                invalidatingClimate: topics.contains(.climate)
            )
        }
    }

    private struct Entry {
        var roster: Roster
        let expires: ContinuousClock.Instant
    }

    enum ChangedTelemetry {
        case charge, climate
    }

    private let lifetime: Duration
    private var scope: String?
    private var entry: Entry?
    private var flight: Task<Roster, Error>?
    private var revision = 0
    private var invalidatedDuringLoad: [String: Set<ChangedTelemetry>] = [:]

    init(lifetime: Duration = .seconds(30)) {
        self.lifetime = lifetime
    }

    func load(
        scope: String,
        requiring vin: String?,
        fetch: @escaping @Sendable () async throws -> Roster
    ) async throws -> Roster {
        if self.scope != scope {
            flight?.cancel()
            flight = nil
            entry = nil
            self.scope = scope
        }
        if let entry, entry.expires > .now,
           vin == nil || entry.roster.vehicles.contains(where: { $0.vin == vin }) {
            return entry.roster
        }

        let task: Task<Roster, Error>
        if let flight {
            task = flight
        } else {
            revision += 1
            invalidatedDuringLoad.removeAll()
            task = Task { try await fetch() }
            flight = task
        }
        let expected = revision
        let result = await task.result
        guard self.scope == scope, revision == expected else { throw CancellationError() }
        if flight != nil {
            flight = nil
            if case .success(var roster) = result {
                for (vin, topics) in invalidatedDuringLoad {
                    roster.invalidate(vin: vin, topics: topics)
                }
                entry = Entry(roster: roster, expires: .now + lifetime)
            } else {
                entry = nil
            }
        }
        try Task.checkCancellation()
        if let entry { return entry.roster }
        return try result.get()
    }

    func cachedVehicle(vin: String, scope: String) -> FleetVehicleInfo? {
        guard self.scope == scope, let entry, entry.expires > .now else { return nil }
        return entry.roster.vehicles.first { $0.vin == vin }
    }

    func invalidateTelemetry(vin: String, scope: String, topic: ChangedTelemetry) {
        guard self.scope == scope else { return }
        if flight != nil { invalidatedDuringLoad[vin, default: []].insert(topic) }
        entry?.roster.invalidate(vin: vin, topics: [topic])
    }
}
