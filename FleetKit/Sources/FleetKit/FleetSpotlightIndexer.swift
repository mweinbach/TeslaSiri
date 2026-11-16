import AppIntents
import CoreSpotlight
import CryptoKit
import Foundation
import OSLog

/// A submitted entity group for Diagnostics. This is our durable view of what
/// the app asked Spotlight to journal; Spotlight does not expose a public
/// "fully visible everywhere" completion signal.
public struct FleetSpotlightSubmittedGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let count: Int
    public let sampleTitles: [String]

    public init(name: String, count: Int, sampleTitles: [String]) {
        self.id = name
        self.name = name
        self.count = count
        self.sampleTitles = sampleTitles
    }
}

public struct FleetSpotlightIndexingReport: Sendable {
    public let indexName: String
    public let submittedAt: Date
    public let groups: [FleetSpotlightSubmittedGroup]
    public let errors: [String]

    public var submittedCount: Int { groups.reduce(0) { $0 + $1.count } }
    public var succeeded: Bool { errors.isEmpty }

    public init(indexName: String, submittedAt: Date, groups: [FleetSpotlightSubmittedGroup], errors: [String]) {
        self.indexName = indexName
        self.submittedAt = submittedAt
        self.groups = groups
        self.errors = errors
    }
}

public struct FleetSpotlightSearchResult: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let contentDescription: String?
    public let keywords: [String]
    public let kind: String?
    public let domainIdentifier: String?

    public init(
        id: String,
        title: String,
        subtitle: String?,
        contentDescription: String?,
        keywords: [String],
        kind: String?,
        domainIdentifier: String?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.contentDescription = contentDescription
        self.keywords = keywords
        self.kind = kind
        self.domainIdentifier = domainIdentifier
    }
}

/// Donates the app's entities to a named Spotlight index so vehicles, live
/// status, drives, charging sessions, software, and release notes are findable in
/// Spotlight search and by Siri without launching the app.
public enum FleetSpotlightIndexer {
    public static let indexName = "FleetEntities"
    /// Most recent drives indexed per vehicle. Older drives stay reachable through
    /// the Find Tesla Drives tool, which queries Tessie directly.
    public static let drivesPerVehicle = 50
    /// Most recent charging sessions indexed per vehicle. Older sessions stay
    /// reachable through the Get Tesla Charging History tool.
    public static let chargesPerVehicle = 50

    /// Dashboard response bytes are retained only within one active refresh.
    public struct DashboardReadings: Sendable {
        public let vin: String
        public var state: Data?
        public var tires: Data?
        public var drives: Data?
        public var driveLimit: Int?
        public var charges: Data?
        public var chargeLimit: Int?
        public var notes: Data?
        public var notesVersion: String?

        public init(vin: String) { self.vin = vin }
    }

    private static let coordinator = SpotlightSyncCoordinator()

    public static func synchronize(vehicles: [FleetVehicleInfo], readings: DashboardReadings?, scope: String) async {
        _ = await coordinator.synchronize(vehicles: vehicles, readings: readings, scope: scope)
    }

    public static func reindexAll() async -> FleetSpotlightIndexingReport {
        let service = FleetIntentService.make()
        do {
            guard let scope = service.sessionScopeID else { throw FleetKitError.notSignedIn }
            let roster = try await service.vehicles()
            return await coordinator.synchronize(vehicles: roster, readings: nil, scope: scope, repair: true)
        } catch {
            return FleetSpotlightIndexingReport(indexName: indexName, submittedAt: Date(), groups: [], errors: [error.localizedDescription])
        }
    }

    public static func search(_ term: String, limit: Int = 20) async throws -> [FleetSpotlightSearchResult] {
        guard limit > 0 else { return [] }
        let start = ContinuousClock.now
        let predicate = queryString(for: term)
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["title", "displayName", "contentDescription", "keywords", "kind"]
        let query = CSSearchQuery(queryString: predicate, queryContext: context)

        var results: [FleetSpotlightSearchResult] = []
        for try await result in query.results {
            let item = result.item
            let attributes = item.attributeSet
            let title = attributes.title ?? attributes.displayName ?? item.uniqueIdentifier
            results.append(
                FleetSpotlightSearchResult(
                    id: item.uniqueIdentifier,
                    title: title,
                    subtitle: attributes.displayName == title ? nil : attributes.displayName,
                    contentDescription: attributes.contentDescription,
                    keywords: attributes.keywords ?? [],
                    kind: attributes.kind,
                    domainIdentifier: item.domainIdentifier
                )
            )
            if results.count >= limit { break }
        }
        let elapsed = FleetKitLog.milliseconds(since: start)
        FleetKitLog.spotlight.info("Search '\(term, privacy: .public)' returned \(results.count, privacy: .public) result(s) in \(elapsed, privacy: .public) ms")
        return results
    }

    public static func donate<Entity: IndexedEntity>(_ entities: [Entity], priority: Int = 0) async throws {
        guard !entities.isEmpty else { return }
        do {
            try await CSSearchableIndex(name: indexName).indexAppEntities(entities, priority: priority)
            FleetKitLog.spotlight.info("Donated \(entities.count, privacy: .public) \(String(describing: Entity.self), privacy: .public) item(s) at priority \(priority, privacy: .public)")
        } catch {
            FleetKitLog.spotlight.error("Donating \(entities.count, privacy: .public) \(String(describing: Entity.self), privacy: .public) item(s) failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public static func deleteAllIndexedEntities() async throws {
        try await coordinator.clear()
    }

    private static func queryString(for rawTerm: String) -> String {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return "title == '*'cd" }
        let escaped = term.replacingOccurrences(of: "'", with: "\\'")
        return "title == '*\(escaped)*'cd || displayName == '*\(escaped)*'cd || contentDescription == '*\(escaped)*'cd || textContent == '*\(escaped)*'cd || keywords == '*\(escaped)*'cd"
    }
}

/// Only identifiers, content digests and coverage times are persisted. A failed or partial
/// read cannot erase records whose absence has not been established by Tessie.
struct SpotlightIndexManifest: Codable {
    struct Group: Codable {
        var digests: [String: Data] = [:]
        var completeAt: Date?
        var version: String?
        var vehicleNameDigest: Data?

        func needsRefresh(at now: Date) -> Bool {
            guard let completeAt else { return true }
            return now.timeIntervalSince(completeAt) >= 15 * 60
        }

        func canUsePage(ids: Set<String>, requested: Int, limit: Int, at now: Date) -> Bool {
            ids.count < requested || requested >= limit || (!needsRefresh(at: now) && ids.isSubset(of: digests.keys))
        }

        func removedIDs(in current: Set<String>, complete: Bool) -> Set<String> {
            complete ? Set(digests.keys).subtracting(current) : []
        }
    }

    var scope: String
    var vehicles: [String: [String: Group]] = [:]
}

private actor SpotlightSyncCoordinator {
    private typealias Group = SpotlightIndexManifest.Group
    private let manifestKey = "FleetSpotlightManifest.v1"
    private let defaults = UserDefaults.standard
    private var tail: Task<Void, Never>?
    private var ticket = 0
    private var maintenanceGeneration = 0
    private var latestMaintenance: Int?
    private var pendingSyncs: [Int: @Sendable () -> Void] = [:]
    private var manifest = SpotlightIndexManifest(scope: "")

    init() {
        if let data = UserDefaults.standard.data(forKey: "FleetSpotlightManifest.v1"),
           let stored = try? JSONDecoder().decode(SpotlightIndexManifest.self, from: data) {
            manifest = stored
        }
    }

    /// Core Spotlight writes can suspend; finish each job (including account clears)
    /// before the next job writes. Each job checks the active account again on entry.
    private func enqueue<T: Sendable>(cancelOnClear: Bool = true, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        ticket += 1
        let current = ticket
        let job = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await work()
        }
        tail = Task { _ = await job.result }
        if cancelOnClear { pendingSyncs[current] = { job.cancel() } }
        defer {
            pendingSyncs[current] = nil
            if ticket == current { tail = nil }
        }
        return try await job.value
    }

    func clear() async throws {
        latestMaintenance = nil
        for cancel in pendingSyncs.values { cancel() }
        try await enqueue(cancelOnClear: false) { try await self.reset(scope: "") }
    }

    private func reset(scope: String) async throws {
        try await CSSearchableIndex(name: FleetSpotlightIndexer.indexName).deleteAllSearchableItems()
        manifest = SpotlightIndexManifest(scope: scope)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(manifest) { defaults.set(data, forKey: manifestKey) }
    }

    func synchronize(
        vehicles: [FleetVehicleInfo], readings: FleetSpotlightIndexer.DashboardReadings?, scope: String, repair: Bool = false
    ) async -> FleetSpotlightIndexingReport {
        maintenanceGeneration += 1
        let generation = maintenanceGeneration
        if !repair { latestMaintenance = generation }
        do {
            return try await enqueue {
                try await self.apply(vehicles: vehicles, readings: readings, scope: scope, repair: repair, generation: generation)
            }
        } catch {
            if !(error is CancellationError) {
                FleetKitLog.spotlight.error("Spotlight sync failed: \(error.localizedDescription, privacy: .private)")
            }
            return .init(indexName: FleetSpotlightIndexer.indexName, submittedAt: Date(), groups: [], errors: [error.localizedDescription])
        }
    }

    private func apply(
        vehicles: [FleetVehicleInfo], readings: FleetSpotlightIndexer.DashboardReadings?, scope: String, repair: Bool, generation: Int
    ) async throws -> FleetSpotlightIndexingReport {
        guard repair || generation == latestMaintenance else { throw CancellationError() }
        let service = FleetIntentService.make()
        guard service.sessionScopeID == scope else { throw CancellationError() }
        if repair || manifest.scope != scope { try await reset(scope: scope) }
        defer { persist() }
        let now = Date()
        var groups: [FleetSpotlightSubmittedGroup] = []
        var errors: [String] = []
        let vins = Set(vehicles.map(\.vin))
        for vin in Set(manifest.vehicles.keys).subtracting(vins) {
            try await removeVehicle(vin)
        }
        for vehicle in vehicles {
            guard service.sessionScopeID == scope else { throw CancellationError() }
            let vin = vehicle.vin
            let samples = readings?.vin == vin ? readings : nil
            func group(_ name: String) -> Group { manifest.vehicles[vin]?[name] ?? Group() }
            func record(_ error: Error, group: String) throws {
                try Task.checkCancellation()
                if service.sessionScopeID != scope { throw CancellationError() }
                switch error {
                case FleetKitError.sessionExpired, FleetKitError.notSignedIn, is CancellationError: throw error
                default: errors.append("\(group): \(error.localizedDescription)")
                }
            }

            let identity = VehicleEntity(info: vehicle)
            // The roster's optional telemetry is independent of the identity registered in Spotlight.
            let fields = [identity.name, identity.model ?? "", identity.color ?? ""]
                + (identity.controls ?? []) + (identity.additionalControls ?? [])
            try await update([(identity, fields)],
                             vin: vin, name: "Vehicles", priority: 10, complete: true, force: repair, groups: &groups)
            let nameDigest = Data(SHA256.hash(data: Data(vehicle.name.utf8)))
            let stateChangedName = group("Live Status").vehicleNameDigest != nameDigest
            var version = group("Software").version
            do {
                let state: (FleetSnapshotInfo, FleetSoftwareInfo)?
                if let data = samples?.state {
                    state = try FleetIntentClient.spotlightState(data, tires: samples?.tires, vin: vin)
                } else if repair || stateChangedName || group("Live Status").needsRefresh(at: now) {
                    state = try await service.snapshotAndSoftware(vin: vin)
                } else { state = nil }
                if let (snapshot, software) = state {
                    guard service.sessionScopeID == scope else { throw CancellationError() }
                    try await update([(VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicle.name), snapshot)],
                                     vin: vin, name: "Live Status", priority: 10, complete: true, force: repair || stateChangedName,
                                     vehicleNameDigest: nameDigest, groups: &groups)
                    version = software.availableVersion ?? software.currentVersion
                    try await update([(SoftwareUpdateEntity(info: software, vin: vin, vehicleName: vehicle.name), software)],
                                     vin: vin, name: "Software", priority: 8, complete: true, force: repair || stateChangedName,
                                     version: version, groups: &groups)
                }
            } catch { try record(error, group: "Status and software") }

            do {
                try await history(
                    vin: vin, name: "Recent Drives", limit: FleetSpotlightIndexer.drivesPerVehicle, force: repair,
                    payload: samples?.drives, requested: samples?.driveLimit, decode: FleetIntentClient.spotlightDrives,
                    fetch: { try await service.drives(vin: vin, limit: $0, requireCompleteRows: true) },
                    entity: DriveEntity.init(info:), scope: scope, groups: &groups
                )
            } catch { try record(error, group: "Recent Drives") }
            do {
                try await history(
                    vin: vin, name: "Charging Sessions", limit: FleetSpotlightIndexer.chargesPerVehicle, force: repair,
                    payload: samples?.charges, requested: samples?.chargeLimit, decode: FleetIntentClient.spotlightCharges,
                    fetch: { try await service.charges(vin: vin, limit: $0, requireCompleteRows: true) },
                    entity: ChargeSessionEntity.init(info:), scope: scope, groups: &groups
                )
            } catch { try record(error, group: "Charging Sessions") }

            do {
                if let version {
                    let notes: [FleetReleaseNoteInfo]?
                    if let data = samples?.notes, samples?.notesVersion == version {
                        notes = try FleetIntentClient.spotlightNotes(data)
                    } else if repair || group("Release Notes").version != version {
                        notes = try await service.releaseNotes(vin: vin, version: version)
                    } else { notes = nil }
                    if let notes {
                        guard service.sessionScopeID == scope else { throw CancellationError() }
                        try await update(notes.map { (ReleaseNoteEntity(info: $0, vin: vin, version: version), $0) },
                                         vin: vin, name: "Release Notes", priority: 2, complete: true,
                                         force: repair, version: version, groups: &groups)
                    }
                }
            } catch { try record(error, group: "Release Notes") }
        }
        guard service.sessionScopeID == scope else { throw CancellationError() }
        if !errors.isEmpty {
            FleetKitLog.spotlight.error("Spotlight sync kept previous rows for \(errors.count, privacy: .public) failed group(s): \(errors.joined(separator: ", "), privacy: .private)")
        }
        return .init(indexName: FleetSpotlightIndexer.indexName, submittedAt: now, groups: groups, errors: errors)
    }

    private func history<Row: Encodable & Identifiable & Sendable, Entity: IndexedEntity>(
        vin: String, name: String, limit: Int, force: Bool, payload: Data?, requested: Int?,
        decode: (Data, String) throws -> ([Row], Int), fetch: (Int) async throws -> [Row],
        entity: (Row) -> Entity, scope: String, groups: inout [FleetSpotlightSubmittedGroup]
    ) async throws where Entity.ID == String, Row.ID == String {
        let group = manifest.vehicles[vin]?[name] ?? Group()
        let rows: [Row]
        let complete: Bool
        if let payload, let requested, requested > 0 {
            let (page, count) = try decode(payload, vin)
            let ids = Set(page.map(\.id))
            guard ids.count == count else { throw FleetKitError.badResponse }
            if group.canUsePage(ids: ids, requested: requested, limit: limit, at: Date()) {
                rows = Array(page.prefix(limit))
                complete = count < requested || requested >= limit
            } else {
                rows = try await fetch(limit)
                complete = true
            }
        } else if force || group.needsRefresh(at: Date()) {
            rows = try await fetch(limit)
            complete = true
        } else { return }
        guard FleetIntentService.make().sessionScopeID == scope else { throw CancellationError() }
        try await update(rows.map { (entity($0), $0) }, vin: vin, name: name, priority: 4,
                         complete: complete, force: force, groups: &groups)
    }

    private func update<Entity: IndexedEntity, Model: Encodable>(
        _ rows: [(Entity, Model)], vin: String, name: String, priority: Int,
        complete: Bool, force: Bool, version: String? = nil, vehicleNameDigest: Data? = nil,
        groups: inout [FleetSpotlightSubmittedGroup]
    ) async throws where Entity.ID == String {
        try Task.checkCancellation()
        var group = manifest.vehicles[vin]?[name] ?? Group()
        var current: Set<String> = []
        var changed: [Entity] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for (entity, model) in rows where current.insert(entity.id).inserted {
            let digest = Data(SHA256.hash(data: try encoder.encode(model)))
            if force || group.digests[entity.id] != digest { changed.append(entity) }
            group.digests[entity.id] = digest
        }
        let removed = group.removedIDs(in: current, complete: complete)
        try await FleetSpotlightIndexer.donate(changed, priority: priority)
        if !removed.isEmpty {
            try await CSSearchableIndex(name: FleetSpotlightIndexer.indexName).deleteAppEntities(identifiedBy: Array(removed), ofType: Entity.self)
            for id in removed { group.digests[id] = nil }
        }
        if complete { group.completeAt = Date() }
        group.version = version
        group.vehicleNameDigest = vehicleNameDigest
        manifest.vehicles[vin, default: [:]][name] = group
        groups.append(.init(name: name, count: changed.count, sampleTitles: changed.prefix(3).map { String(localized: $0.displayRepresentation.title) }))
    }

    private func removeVehicle(_ vin: String) async throws {
        func remove<E: IndexedEntity>(_ type: E.Type, _ name: String) async throws where E.ID == String {
            guard let ids = manifest.vehicles[vin]?[name]?.digests.keys, !ids.isEmpty else { return }
            try await CSSearchableIndex(name: FleetSpotlightIndexer.indexName).deleteAppEntities(identifiedBy: Array(ids), ofType: type)
        }
        try await remove(VehicleEntity.self, "Vehicles")
        try await remove(VehicleStatusEntity.self, "Live Status")
        try await remove(DriveEntity.self, "Recent Drives")
        try await remove(ChargeSessionEntity.self, "Charging Sessions")
        try await remove(SoftwareUpdateEntity.self, "Software")
        try await remove(ReleaseNoteEntity.self, "Release Notes")
        manifest.vehicles[vin] = nil
    }
}
