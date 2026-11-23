import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation

/// The software-update status for a vehicle, indexed in Spotlight.
public struct SoftwareUpdateEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Software Update",
        synonyms: ["Car Software Update", "Tesla Software Update", "Firmware Update"]
    )
    public static let defaultQuery = SoftwareUpdateEntityQuery()

    /// "software:<VIN>" — namespaced so it can't collide with other VIN-keyed
    /// entity types in the shared Spotlight index, where the identifier is the
    /// primary key and collisions overwrite.
    public let id: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Vehicle Name", description: "The owner's name for the car this update is for.", indexingKey: \.title)
    public var vehicleName: String

    @Property(title: "Current Version", description: "The software version installed on the car now, such as 2026.32.5.")
    public var currentVersion: String?

    @Property(title: "Available Version", description: "The software version waiting to install, such as 2026.38.1. Empty when the car is up to date.")
    public var availableVersion: String?

    @Property(title: "Update Available", description: "Whether a newer software version is downloading, ready, scheduled, or installing.")
    public var updateAvailable: Bool

    @Property(title: "Installable Now", description: "Whether the update has finished downloading and can be installed right now.")
    public var installable: Bool

    @Property(title: "Status", description: "Update status reported by the car: available (ready to install), downloading, downloading_wifi_wait (waiting for Wi-Fi), scheduled, or installing. Empty when up to date.")
    public var status: String?

    @Property(title: "Download Progress (%)", description: "How much of the update has downloaded, from 0 to 100.")
    public var downloadPercent: Int?

    @Property(title: "Install Progress (%)", description: "How far the installation has gone, from 0 to 100, while installing.")
    public var installPercent: Int?

    @Property(title: "Expected Duration (Minutes)", description: "How long the installation is expected to take, in minutes. The car can't be driven while it installs.")
    public var expectedDurationMinutes: Int?

    public init(info: FleetSoftwareInfo, vin: String, vehicleName: String) {
        self.id = Self.entityID(forVIN: vin)
        self.vin = vin
        self.vehicleName = vehicleName
        self.currentVersion = info.currentVersion
        self.availableVersion = info.availableVersion
        self.updateAvailable = info.updateAvailable
        self.installable = info.installable
        self.status = info.status
        self.downloadPercent = info.downloadPercent.map { Int($0.rounded()) }
        self.installPercent = info.installPercent.map { Int($0.rounded()) }
        self.expectedDurationMinutes = info.expectedDurationMinutes.map { Int($0.rounded()) }
    }

    public static func entityID(forVIN vin: String) -> String {
        "software:\(vin)"
    }

    /// Accepts bare VINs too so identifiers saved before namespacing still resolve.
    public static func vin(fromEntityID id: String) -> String {
        id.hasPrefix("software:") ? String(id.dropFirst("software:".count)) : id
    }

    public var headline: String {
        if updateAvailable, let availableVersion {
            return "Update available: \(availableVersion)"
        }
        if let currentVersion {
            return "Up to date: \(currentVersion)"
        }
        return "Software"
    }

    public var detailText: String {
        if let installPercent { return "Installing • \(installPercent)%" }
        if let downloadPercent { return "Downloading • \(downloadPercent)%" }
        if let status, !status.isEmpty { return status.capitalized }
        return currentVersion.map { "Current \($0)" } ?? ""
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(vehicleName) - \(headline)", subtitle: "\(detailText)")
    }

    /// One or two sentences for Siri describing where the update stands.
    public var spokenStatus: String {
        guard updateAvailable else {
            return currentVersion.map { "\(vehicleName) is up to date on \($0)." } ?? "\(vehicleName) has no software update waiting."
        }
        let target = availableVersion.map { "Software update \($0)" } ?? "A software update"
        let duration = expectedDurationMinutes.map { " Installing takes about \($0) minutes, and the car can't be driven during it." } ?? ""
        switch status?.lowercased() ?? "" {
        case "installing":
            return "\(target) is installing on \(vehicleName)" + (installPercent.map { ", \($0)% done." } ?? ".")
        case "scheduled":
            return "\(target) is scheduled to install on \(vehicleName)." + duration
        case "downloading":
            return "\(target) is downloading to \(vehicleName)" + (downloadPercent.map { ", \($0)% done." } ?? ".")
        case "downloading_wifi_wait":
            return "\(target) is waiting for Wi-Fi to finish downloading to \(vehicleName)" + (downloadPercent.map { " (\($0)% done)." } ?? ".")
        default:
            return installable
                ? "\(target) is ready to install on \(vehicleName)." + duration
                : "\(target) is available for \(vehicleName)."
        }
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        var parts = [headline]
        if let currentVersion { parts.append("Current version \(currentVersion)") }
        if let availableVersion { parts.append("Available version \(availableVersion)") }
        if let status { parts.append("Status \(status)") }
        if installable { parts.append("Installable now") }
        let description = "Tesla software update for \(vehicleName). \(parts.joined(separator: ". "))."
        attributes.title = "\(vehicleName) Software"
        attributes.displayName = "\(vehicleName) software update"
        attributes.kind = "Tesla Software Update"
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            vehicleName, FleetKitLog.vin(vin), "Tesla", "software", "software update", "release", "release version",
            "version", "install", "download", "update available", currentVersion, availableVersion, status
        ].compactMap { $0 }
        return attributes
    }
}

public struct SoftwareUpdateEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    public init() {}

    public func entities(for identifiers: [SoftwareUpdateEntity.ID]) async throws -> [SoftwareUpdateEntity] {
        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        var results: [SoftwareUpdateEntity] = []
        for identifier in identifiers {
            let vin = SoftwareUpdateEntity.vin(fromEntityID: identifier)
            guard let vehicle = vehicles.first(where: { $0.vin == vin }) else { continue }
            let info = try await service.software(vin: vin)
            results.append(SoftwareUpdateEntity(info: info, vin: vin, vehicleName: vehicle.name))
        }
        return results
    }

    public func suggestedEntities() async throws -> [SoftwareUpdateEntity] {
        let service = FleetIntentService.make()
        let vehicle = try await service.resolvedVehicle(nil)
        let info = try await service.software(vin: vehicle.vin)
        return [SoftwareUpdateEntity(info: info, vin: vehicle.vin, vehicleName: vehicle.name)]
    }

    public func entities(matching string: String) async throws -> [SoftwareUpdateEntity] {
        let service = FleetIntentService.make()
        let selectedVIN = FleetSharedTokenStore.shared.selectedVIN()
        var vehicles = try await service.vehicles()
        if let index = vehicles.firstIndex(where: { $0.vin == selectedVIN }), index != vehicles.startIndex {
            let selected = vehicles.remove(at: index)
            vehicles.insert(selected, at: 0)
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let namedMatches = trimmed.isEmpty ? [] : vehicles.filter { $0.name.localizedStandardContains(trimmed) }
        if !namedMatches.isEmpty {
            vehicles = namedMatches
        }

        let genericTerms = ["software", "update", "firmware", "version", "car", "vehicle", "tesla"]
        let isGeneric = trimmed.isEmpty || genericTerms.contains(where: { trimmed.contains($0) })

        var results: [SoftwareUpdateEntity] = []
        for vehicle in vehicles {
            let info = try await service.software(vin: vehicle.vin)
            let entity = SoftwareUpdateEntity(info: info, vin: vehicle.vin, vehicleName: vehicle.name)
            if isGeneric || !namedMatches.isEmpty
                || (entity.currentVersion?.localizedStandardContains(trimmed) == true)
                || (entity.availableVersion?.localizedStandardContains(trimmed) == true)
                || (entity.status?.localizedStandardContains(trimmed) == true) {
                results.append(entity)
            }
        }
        return results
    }

    public func reindexEntities(for identifiers: [SoftwareUpdateEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let service = FleetIntentService.make()
        var all: [SoftwareUpdateEntity] = []
        for vehicle in try await service.vehicles() {
            let info = try await service.software(vin: vehicle.vin)
            all.append(SoftwareUpdateEntity(info: info, vin: vehicle.vin, vehicleName: vehicle.name))
        }
        try await FleetSpotlightIndexer.donate(all)
    }
}

extension SoftwareUpdateEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.spokenStatus)
    }
}

/// A single software release note, indexed so notes are searchable in Spotlight.
public struct ReleaseNoteEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Release Note")
    public static let defaultQuery = ReleaseNoteEntityQuery()

    public let id: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Software Version", description: "The software version these release notes describe, such as 2026.38.1.")
    public var version: String?

    @Property(title: "Feature Title", description: "The name of the new feature or change, such as \"Dashcam Viewer\".", indexingKey: \.title)
    public var title: String

    @Property(title: "Feature Subtitle", description: "A short category or tagline for the feature.")
    public var subtitle: String?

    @Property(title: "Release Note Details", description: "Tesla's full description of the feature, in plain text.", indexingKey: \.textContent)
    public var details: String?

    public init(info: FleetReleaseNoteInfo, vin: String, version: String?) {
        self.id = Self.entityID(forVIN: vin, version: version, noteID: info.id)
        self.vin = vin
        self.version = version
        self.title = Self.cleanText(info.title) ?? info.title
        self.subtitle = info.subtitle.flatMap(Self.cleanText)
        self.details = info.details.flatMap(Self.cleanText) ?? info.subtitle.flatMap(Self.cleanText)
    }

    public static func entityID(forVIN vin: String, version: String?, noteID: String) -> String {
        [vin, version, noteID].compactMap { $0 }.joined(separator: ":")
    }

    /// Clean, single-line summary suitable for Siri spoken readout.
    public var spokenItemSummary: String {
        let heading: String
        if let subtitle, !subtitle.isEmpty, subtitle.caseInsensitiveCompare(title) != .orderedSame {
            heading = "\(title) (\(subtitle))"
        } else {
            heading = title
        }

        guard let details, !details.isEmpty, details.caseInsensitiveCompare(subtitle ?? "") != .orderedSame else {
            return heading
        }

        let concise = Self.firstSentenceOrTruncated(details, maxCharacters: 140)
        return "\(heading): \(concise)"
    }

    public static func spokenDigest(
        for notes: [ReleaseNoteEntity],
        version: String,
        vehicleName: String,
        featureQuery: String? = nil
    ) -> String {
        let trimmedQuery = featureQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            if let trimmedQuery, !trimmedQuery.isEmpty {
                return "No release notes matching \"\(trimmedQuery)\" were found for version \(version) on \(vehicleName)."
            }
            return "No release notes were found for version \(version) on \(vehicleName)."
        }

        let maxSpokenItems = 4
        let spokenItems = notes.prefix(maxSpokenItems).map(\.spokenItemSummary).joined(separator: " ")
        let remaining = notes.count - min(notes.count, maxSpokenItems)
        let suffix = remaining > 0 ? " Plus \(remaining) more feature update\(remaining == 1 ? "" : "s")." : ""

        if let trimmedQuery, !trimmedQuery.isEmpty {
            return "Version \(version) on \(vehicleName) has \(notes.count) release note\(notes.count == 1 ? "" : "s") matching \"\(trimmedQuery)\". \(spokenItems)\(suffix)"
        }
        return "Version \(version) on \(vehicleName) includes \(notes.count) release note\(notes.count == 1 ? "" : "s"). \(spokenItems)\(suffix)"
    }

    public var displayRepresentation: DisplayRepresentation {
        let repSubtitle = [version.map { "Version \($0)" }, subtitle, details]
            .compactMap { $0 }
            .reduce(into: [String]()) { acc, item in
                if !acc.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                    acc.append(item)
                }
            }
            .joined(separator: " • ")
        return DisplayRepresentation(title: "\(title)", subtitle: "\(repSubtitle)")
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let description = ["Tesla release note", version.map { "Version \($0)" }, title, subtitle, details]
            .compactMap { $0 }
            .joined(separator: ". ")
        attributes.title = title
        attributes.displayName = version.map { "\(title) \($0)" } ?? title
        attributes.kind = "Tesla Release Note"
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            "Tesla", "release note", "release version", "software", "update", "version",
            FleetKitLog.vin(vin), version, title, subtitle, details
        ].compactMap { $0 }
        return attributes
    }

    static func cleanText(_ raw: String) -> String? {
        var text = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•*-")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstSentenceOrTruncated(_ text: String, maxCharacters: Int) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= maxCharacters {
            return normalized.hasSuffix(".") || normalized.hasSuffix("!") || normalized.hasSuffix("?")
                ? normalized
                : "\(normalized)."
        }
        if let dotRange = normalized.range(of: ". "),
           normalized.distance(from: normalized.startIndex, to: dotRange.lowerBound) <= maxCharacters {
            return String(normalized[...dotRange.lowerBound])
        }
        let cutoff = normalized.index(normalized.startIndex, offsetBy: maxCharacters)
        let slice = String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(slice)…"
    }
}

extension ReleaseNoteEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.transferSummary)
    }

    /// Human-readable release note text for sharing with other apps (never exposes the VIN).
    public var transferSummary: String {
        let prefix = version.map { "Version \($0) — " } ?? ""
        if let details, !details.isEmpty {
            return "\(prefix)\(title): \(details)"
        }
        return "\(prefix)\(spokenItemSummary)"
    }
}

public struct ReleaseNoteEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    private let serviceOverride: FleetIntentService?

    private var service: FleetIntentService {
        serviceOverride ?? .make()
    }

    public init() {
        self.serviceOverride = nil
    }

    init(service: FleetIntentService) {
        self.serviceOverride = service
    }

    public func entities(for identifiers: [ReleaseNoteEntity.ID]) async throws -> [ReleaseNoteEntity] {
        guard !identifiers.isEmpty else { return [] }
        let authorizedVINs = Set(try await service.vehicles().map(\.vin))
        var versionsByVIN: [String: Set<String>] = [:]
        for identifier in identifiers {
            let parts = identifier.split(separator: ":", maxSplits: 2)
            guard parts.count == 3, authorizedVINs.contains(String(parts[0])) else { continue }
            versionsByVIN[String(parts[0]), default: []].insert(String(parts[1]))
        }

        var notesByID: [ReleaseNoteEntity.ID: ReleaseNoteEntity] = [:]
        for (vin, versions) in versionsByVIN {
            for version in versions {
                for note in try await service.releaseNotes(vin: vin, version: version) {
                    let entity = ReleaseNoteEntity(info: note, vin: vin, version: version)
                    notesByID[entity.id] = entity
                }
            }
        }
        return identifiers.compactMap { notesByID[$0] }
    }

    public func entities(matching string: String) async throws -> [ReleaseNoteEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = try await allReleaseNotes()
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.subtitle?.localizedCaseInsensitiveContains(query) == true
                || note.details?.localizedCaseInsensitiveContains(query) == true
                || note.version?.localizedCaseInsensitiveContains(query) == true
        }
    }

    public func suggestedEntities() async throws -> [ReleaseNoteEntity] {
        let vehicle = try await service.resolvedVehicle(nil)
        return try await latestReleaseNotes(vin: vehicle.vin)
    }

    public func reindexEntities(for identifiers: [ReleaseNoteEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(allReleaseNotes())
    }

    private func allReleaseNotes() async throws -> [ReleaseNoteEntity] {
        var all: [ReleaseNoteEntity] = []
        for vehicle in try await service.vehicles() {
            do {
                all.append(contentsOf: try await latestReleaseNotes(vin: vehicle.vin))
            } catch FleetKitError.sessionExpired {
                throw FleetKitError.sessionExpired
            } catch {
                continue
            }
        }
        return all
    }

    private func latestReleaseNotes(vin: String) async throws -> [ReleaseNoteEntity] {
        let software = try await service.software(vin: vin)
        guard let version = software.availableVersion ?? software.currentVersion else { return [] }
        return try await service.releaseNotes(vin: vin, version: version)
            .map { ReleaseNoteEntity(info: $0, vin: vin, version: version) }
    }
}
