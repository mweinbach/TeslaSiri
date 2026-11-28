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
    /// Most recent drives indexed per vehicle, so Siri can find a drive by place or date
    /// itself. It matches how far back `DriveEntityQuery` can look a drive up again. Find
    /// Drives reaches older drives when a request gives a date range.
    public static let drivesPerVehicle = FleetIntentService.driveHistoryPageSize * FleetIntentService.driveHistoryMaxPages
    /// Most recent charging sessions indexed per vehicle, which is also how far back
    /// `ChargeSessionEntityQuery` looks a session up. Get Charging History reaches older
    /// sessions when a request gives a date range.
    public static let chargesPerVehicle = 200
    /// Newest charging sessions read between full reads of the window.
    static let chargePageSize = 50

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
        /// How a page of a history group's newest rows can be applied.
        enum PageUse: Equatable {
            /// The page is the whole window: a short page, or one as long as the window.
            case window
            /// The page overlaps what is indexed, so its rows are merged in and none are removed.
            case merge
        }

        /// How long a history window is trusted before it is read again in full, which picks
        /// up edits and deletions older than the newest page.
        static let windowInterval: TimeInterval = 24 * 60 * 60

        var digests: [String: Data] = [:]
        /// When a read last established the group's whole contents, which allows removing rows.
        var completeAt: Date?
        /// History groups: when the newest rows were last merged in between window reads.
        var mergedAt: Date?
        /// History groups: when the whole window was last read, and how many rows it asked for.
        var windowAt: Date?
        var window: Int?
        var version: String?
        var vehicleNameDigest: Data?

        func needsRefresh(at now: Date) -> Bool {
            guard let latest = [completeAt, mergedAt, windowAt].compactMap({ $0 }).max() else { return true }
            return now.timeIntervalSince(latest) >= 15 * 60
        }

        /// A history window is read in full the first time, when its size changes, and once
        /// it is older than `windowInterval`.
        func needsWindowRead(limit: Int, at now: Date) -> Bool {
            guard let windowAt, window == limit else { return true }
            return now.timeIntervalSince(windowAt) >= Self.windowInterval
        }

        /// How a page of the newest rows can be applied, or `nil` when the window has to be
        /// read instead: it is due, or the page shares no row with the index, so rows between
        /// the two may be missing. A page that lost rows it couldn't decode (`intact` false)
        /// never counts as the whole window.
        func use(ofPage ids: Set<String>, requested: Int, limit: Int, intact: Bool = true, at now: Date) -> PageUse? {
            if intact, ids.count < requested || requested >= limit { return .window }
            if !needsWindowRead(limit: limit, at: now), !ids.isDisjoint(with: digests.keys) { return .merge }
            return nil
        }

        mutating func noteHistoryRead(spansWindow: Bool, limit: Int, at now: Date) {
            if spansWindow {
                windowAt = now
                window = limit
            } else {
                mergedAt = now
            }
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
    private let defaults: UserDefaults
    private var tail: Task<Void, Never>?
    private var ticket = 0
    private var maintenanceGeneration = 0
    private var latestMaintenance: Int?
    private var pendingSyncs: [Int: @Sendable () -> Void] = [:]
    private var manifest = SpotlightIndexManifest(scope: "")

    init() {
        let sharedDefaults = UserDefaults(suiteName: FleetKitConfig.appGroupIdentifier) ?? .standard
        self.defaults = sharedDefaults

        if let data = sharedDefaults.data(forKey: "FleetSpotlightManifest.v1"),
           let stored = try? JSONDecoder().decode(SpotlightIndexManifest.self, from: data) {
            manifest = stored
        } else if sharedDefaults !== UserDefaults.standard,
                  let legacyData = UserDefaults.standard.data(forKey: "FleetSpotlightManifest.v1"),
                  let stored = try? JSONDecoder().decode(SpotlightIndexManifest.self, from: legacyData) {
            manifest = stored
            sharedDefaults.set(legacyData, forKey: "FleetSpotlightManifest.v1")
            UserDefaults.standard.removeObject(forKey: "FleetSpotlightManifest.v1")
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
        do {
            let service = FleetIntentService.make()
            guard service.sessionScopeID == scope else { throw CancellationError() }
            maintenanceGeneration += 1
            let generation = maintenanceGeneration
            if !repair { latestMaintenance = generation }
            return try await enqueue {
                try await self.apply(vehicles: vehicles, readings: readings, scope: scope, repair: repair,
                                     generation: generation, service: service)
            }
        } catch {
            if !(error is CancellationError) {
                FleetKitLog.spotlight.error("Spotlight sync failed: \(error.localizedDescription, privacy: .private)")
            }
            return .init(indexName: FleetSpotlightIndexer.indexName, submittedAt: Date(), groups: [], errors: [error.localizedDescription])
        }
    }

    private func apply(
        vehicles: [FleetVehicleInfo], readings: FleetSpotlightIndexer.DashboardReadings?, scope: String, repair: Bool,
        generation: Int, service: FleetIntentService
    ) async throws -> FleetSpotlightIndexingReport {
        guard repair || generation == latestMaintenance else { throw CancellationError() }
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
        let defaultVIN = service.defaultVehicle(in: vehicles)?.vin
        let ownerName = service.ownerDisplayName
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

            let isDefault = (vin == defaultVIN)
            let identity = VehicleEntity(info: vehicle, usesTeslascope: service.usesTeslascope, ownerName: ownerName)
            identity.isDefaultCar = isDefault
            // The roster's optional telemetry is independent of the identity registered in Spotlight.
            let fields = [identity.name, identity.model ?? "", identity.color ?? "", ownerName ?? "", isDefault ? "default" : "secondary"]
                + (identity.controls ?? []) + (identity.additionalControls ?? [])
            try await update([(identity, fields)],
                             vin: vin, name: "Vehicles", priority: 10, complete: true, force: repair, groups: &groups)
            let nameDigest = Data(SHA256.hash(data: Data("\(vehicle.name)|\(ownerName ?? "")|\(isDefault)".utf8)))
            let stateChangedName = group("Live Status").vehicleNameDigest != nameDigest
            var version = group("Software").version
            var indexedStatus: VehicleStatusEntity?
            do {
                let state: (FleetSnapshotInfo, FleetSoftwareInfo)?
                if let data = samples?.state {
                    state = try FleetIntentClient.spotlightState(data, tires: samples?.tires, vin: vin)
                } else if repair || stateChangedName || group("Live Status").needsRefresh(at: now) {
                    state = try await service.snapshotAndSoftware(vin: vin)
                } else { state = nil }
                if let (snapshot, software) = state {
                    guard service.sessionScopeID == scope else { throw CancellationError() }
                    let statusEntity = VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicle.name, ownerName: ownerName)
                    indexedStatus = statusEntity
                    try await update([(statusEntity, snapshot)],
                                     vin: vin, name: "Live Status", priority: 10, complete: true, force: repair || stateChangedName,
                                     vehicleNameDigest: nameDigest, groups: &groups)
                    version = software.availableVersion ?? software.currentVersion
                    try await update([(SoftwareUpdateEntity(info: software, vin: vin, vehicleName: vehicle.name, ownerName: ownerName), software)],
                                     vin: vin, name: "Software", priority: 8, complete: true, force: repair || stateChangedName,
                                     version: version, groups: &groups)
                }
            } catch { try record(error, group: "Status and software") }

            do {
                if repair || stateChangedName || indexedStatus != nil || group("Car Action Anchors").digests.isEmpty {
                    let companionItems = FleetSpotlightNaming.companionSearchItems(
                        for: identity, status: indexedStatus, ownerName: ownerName
                    )
                    try await CSSearchableIndex(name: FleetSpotlightIndexer.indexName).indexSearchableItems(companionItems)
                    var anchorGroup = group("Car Action Anchors")
                    for item in companionItems {
                        anchorGroup.digests[item.uniqueIdentifier] = nameDigest
                    }
                    anchorGroup.vehicleNameDigest = nameDigest
                    anchorGroup.completeAt = now
                    manifest.vehicles[vin, default: [:]]["Car Action Anchors"] = anchorGroup
                    groups.append(.init(
                        name: "Car Action Anchors",
                        count: companionItems.count,
                        sampleTitles: companionItems.compactMap { $0.attributeSet.title }
                    ))
                }
            } catch { try record(error, group: "Car Action Anchors") }

            let placeStore = FleetSharedPlaceStore(appGroup: service.appGroupIdentifier)
            let knownPlaces = placeStore.places(forVIN: vin)
            let placesDigest = placeStore.digest(forVIN: vin)
            let historyIdentityDigest = placesDigest.isEmpty
                ? nameDigest
                : Data(SHA256.hash(data: nameDigest + placesDigest))

            do {
                let pageSize = FleetIntentService.driveHistoryPageSize
                try await history(
                    vin: vin, name: "Recent Drives", limit: FleetSpotlightIndexer.drivesPerVehicle, pageSize: pageSize,
                    nameDigest: historyIdentityDigest, force: repair,
                    payload: samples?.drives, requested: samples?.driveLimit, decode: FleetIntentClient.spotlightDrives,
                    fetch: { limit in
                        try await self.tolerantRead { strict in
                            let pages = (limit + pageSize - 1) / pageSize
                            let drives = try await service.driveHistory(vin: vin, maxPages: pages, requireCompleteRows: strict)
                            return Array(drives.prefix(limit))
                        }
                    },
                    entity: { DriveEntity(info: $0, vehicleName: vehicle.name, knownPlaces: knownPlaces) }, scope: scope, groups: &groups
                )
            } catch { try record(error, group: "Recent Drives") }
            do {
                try await history(
                    vin: vin, name: "Charging Sessions", limit: FleetSpotlightIndexer.chargesPerVehicle,
                    pageSize: FleetSpotlightIndexer.chargePageSize, nameDigest: historyIdentityDigest, force: repair,
                    payload: samples?.charges, requested: samples?.chargeLimit, decode: FleetIntentClient.spotlightCharges,
                    fetch: { limit in
                        try await self.tolerantRead { strict in
                            try await service.charges(vin: vin, limit: limit, requireCompleteRows: strict)
                        }
                    },
                    entity: { ChargeSessionEntity(info: $0, vehicleName: vehicle.name, knownPlaces: knownPlaces) }, scope: scope, groups: &groups
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

    /// A strict read fails when the provider returns a row it can't decode. This reads again
    /// without that requirement and reports the result as not intact, so one bad row doesn't
    /// keep the rest of the history out of the index, and nothing is removed on the evidence
    /// of a partial read.
    private func tolerantRead<Row>(
        _ read: (_ strict: Bool) async throws -> [Row]
    ) async throws -> (rows: [Row], intact: Bool) {
        do {
            return (try await read(true), true)
        } catch FleetKitError.badResponse {
            return (try await read(false), false)
        }
    }

    /// Keeps a deep window of history indexed without reading it all on every refresh. The
    /// whole window is read once a day, when its size changes, and when the car is renamed
    /// (indexed rows carry the car's name). In between, a page of the newest rows is merged
    /// in, as long as it overlaps what is already indexed.
    private func history<Row: Encodable & Identifiable & Sendable, Entity: IndexedEntity>(
        vin: String, name: String, limit: Int, pageSize: Int, nameDigest: Data, force: Bool,
        payload: Data?, requested: Int?,
        decode: (Data, String) throws -> ([Row], Int),
        fetch: (Int) async throws -> (rows: [Row], intact: Bool),
        entity: (Row) -> Entity, scope: String, groups: inout [FleetSpotlightSubmittedGroup]
    ) async throws where Entity.ID == String, Row.ID == String {
        let group = manifest.vehicles[vin]?[name] ?? Group()
        let now = Date()
        let force = force || group.vehicleNameDigest != nameDigest
        var newest: (rows: [Row], requested: Int, intact: Bool)?
        if force {
            newest = nil
        } else if let payload, let requested, requested > 0 {
            let (page, count) = try decode(payload, vin)
            guard Set(page.map(\.id)).count == count else { throw FleetKitError.badResponse }
            newest = (page, requested, true)
        } else if group.needsWindowRead(limit: limit, at: now) {
            newest = nil
        } else if group.needsRefresh(at: now) {
            let page = try await fetch(pageSize)
            newest = (page.rows, pageSize, page.intact)
        } else { return }

        let rows: [Row]
        let spansWindow: Bool
        let intact: Bool
        if let newest,
           let use = group.use(ofPage: Set(newest.rows.map(\.id)), requested: newest.requested, limit: limit,
                               intact: newest.intact, at: now) {
            rows = Array(newest.rows.prefix(limit))
            spansWindow = use == .window
            intact = newest.intact
        } else {
            let window = try await fetch(limit)
            rows = window.rows
            spansWindow = true
            intact = window.intact
        }
        guard FleetIntentService.make().sessionScopeID == scope else { throw CancellationError() }
        try await update(rows.map { (entity($0), $0) }, vin: vin, name: name, priority: 4,
                         complete: spansWindow && intact, force: force, vehicleNameDigest: nameDigest, groups: &groups)
        manifest.vehicles[vin]?[name]?.noteHistoryRead(spansWindow: spansWindow, limit: limit, at: now)
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
        let companionIDs = FleetSpotlightNaming.companionItemIdentifiers(forVIN: vin)
        try await CSSearchableIndex(name: FleetSpotlightIndexer.indexName).deleteSearchableItems(withIdentifiers: companionIDs)
        manifest.vehicles[vin] = nil
    }
}
