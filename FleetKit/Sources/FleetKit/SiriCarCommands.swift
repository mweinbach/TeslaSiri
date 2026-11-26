import Foundation

/// Backs the SiriKit Car Commands and Maps EV routing handlers in the `TeslaSiriCarIntents`
/// extension. It returns plain values so the logic builds and runs on every FleetKit platform;
/// the iOS-only extension maps them to `IN*` intent responses.
public struct SiriCarCommandService: Sendable {
    public enum CarResolution: Sendable {
        case car(FleetVehicleInfo)
        case ambiguous([FleetVehicleInfo])
        case noMatch
    }

    private let service: FleetIntentService

    public init(service: FleetIntentService = .make()) {
        self.service = service
    }

    // MARK: - Car names

    /// Matches Siri's car name (or a VIN carried as the vocabulary identifier) against the roster.
    /// A generic name ("my car", "Tesla") selects the default car.
    public func resolveCar(identifier: String?, spokenName: String?) async throws -> CarResolution {
        let roster = try await service.vehicles()
        return Self.match(
            identifier: identifier,
            spokenName: spokenName,
            roster: roster,
            defaultVehicle: service.defaultVehicle(in: roster)
        )
    }

    static func match(
        identifier: String?,
        spokenName: String?,
        roster: [FleetVehicleInfo],
        defaultVehicle: FleetVehicleInfo?
    ) -> CarResolution {
        guard !roster.isEmpty else { return .noMatch }
        if let identifier, let vehicle = roster.first(where: { $0.vin == identifier }) {
            return .car(vehicle)
        }

        let phrase = normalizedCarName(spokenName ?? "")
        if genericCarNames.contains(phrase) {
            return defaultVehicle.map(CarResolution.car) ?? .noMatch
        }

        let exact = roster.filter { normalizedCarName($0.name) == phrase }
        if exact.count == 1 { return .car(exact[0]) }
        if exact.count > 1 { return .ambiguous(exact) }

        let partial = roster.filter { vehicle in
            let name = normalizedCarName(vehicle.name)
            if !name.isEmpty, name.contains(phrase) || phrase.contains(name) { return true }
            guard let model = vehicle.modelName.map(normalizedCarName) else { return false }
            return phrase == model || phrase == "tesla \(model)"
        }
        if partial.count == 1 { return .car(partial[0]) }
        if partial.count > 1 { return .ambiguous(partial) }
        return roster.count == 1 ? .car(roster[0]) : .noMatch
    }

    private static let genericCarNames: Set<String> = ["", "car", "vehicle", "tesla", "truck", "ev", "auto", "automobile"]

    static func normalizedCarName(_ name: String) -> String {
        var words = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        while let first = words.first, ["my", "the", "our"].contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    // MARK: - Locks and signals

    public func isLocked(vin: String) async throws -> Bool? {
        let vehicle = try await service.resolvedVehicle(vin)
        return try await service.snapshot(for: vehicle, topics: [.security]).locked
    }

    /// Sends the lock change. A sleeping car gets the request without waiting for it to wake.
    public func setLocked(_ locked: Bool, vin: String) async throws -> VehicleCommandDeliveryState {
        try await service.runControl(
            action: locked ? "door_lock" : "door_unlock",
            vin: vin,
            humanName: locked ? "locking" : "unlocking",
            allowAsyncWake: true
        )
    }

    /// Flashes the lights and/or honks the horn, one command at a time.
    public func activateSignals(flashLights: Bool, honkHorn: Bool, vin: String) async throws -> VehicleCommandDeliveryState {
        var delivery = VehicleCommandDeliveryState.confirmed
        if flashLights {
            let state = try await service.runControl(action: "flash_lights", vin: vin, humanName: "flashing the lights", allowAsyncWake: true)
            if state == .wakingVehicle { delivery = .wakingVehicle }
        }
        if honkHorn {
            let state = try await service.runControl(action: "honk_horn", vin: vin, humanName: "honking the horn", allowAsyncWake: true)
            if state == .wakingVehicle { delivery = .wakingVehicle }
        }
        return delivery
    }

    // MARK: - Power level (Siri and Maps)

    public func powerLevel(vin: String) async throws -> SiriCarPowerLevel {
        let vehicle = try await service.resolvedVehicle(vin)
        let snapshot = try await service.snapshot(for: vehicle, topics: [.battery, .range, .charging])
        return SiriCarPowerLevel(snapshot: snapshot)
    }

    // MARK: - Maps EV routing

    /// The account's cars, default car first, for Maps' List Cars request.
    public func cars(regionCode: String? = Locale.current.region?.identifier) async throws -> [SiriCarDescriptor] {
        let roster = try await service.vehicles()
        let defaultVIN = service.defaultVehicle(in: roster)?.vin
        let ordered = roster.filter { $0.vin == defaultVIN } + roster.filter { $0.vin != defaultVIN }
        let ports = SiriCarChargingPort.ports(forRegion: regionCode)
        return ordered.map { SiriCarDescriptor(vehicle: $0, chargingPorts: ports) }
    }
}

/// A car's charge and range in the units SiriKit expects.
public struct SiriCarPowerLevel: Sendable, Equatable {
    public var vin: String
    /// State of charge from 0 to 1.
    public var chargeFraction: Double?
    public var rangeMiles: Double?
    /// Rated range at 100%, estimated from the current range and charge.
    public var fullRangeMiles: Double?
    public var isCharging: Bool?
    public var minutesToFull: Int?
    public var updatedAt: Date?

    init(snapshot: FleetSnapshotInfo) {
        vin = snapshot.vin
        let level = snapshot.batteryLevel.map { min(max($0, 0), 100) }
        chargeFraction = level.map { $0 / 100 }
        rangeMiles = snapshot.batteryRangeMiles
        if let level, level > 0, let range = snapshot.batteryRangeMiles {
            fullRangeMiles = range / (level / 100)
        }
        isCharging = snapshot.chargingState.map { $0.caseInsensitiveCompare("Charging") == .orderedSame }
        if isCharging == true, let hours = snapshot.timeToFullCharge, hours > 0 {
            minutesToFull = Int((hours * 60).rounded())
        }
        updatedAt = snapshot.updatedAtDate
    }
}

/// One car for Maps EV routing.
public struct SiriCarDescriptor: Sendable, Equatable {
    public var vin: String
    public var displayName: String
    public var make: String
    public var model: String?
    public var year: String?
    public var chargingPorts: [SiriCarChargingPort]

    init(vehicle: FleetVehicleInfo, chargingPorts: [SiriCarChargingPort]) {
        vin = vehicle.vin
        displayName = vehicle.name
        make = "Tesla"
        model = vehicle.modelName
        year = Self.modelYear(vin: vehicle.vin)
        self.chargingPorts = chargingPorts
    }

    /// The model year encoded in the VIN's 10th character, for 2010 and later.
    static func modelYear(vin: String) -> String? {
        let characters = Array(vin.uppercased())
        guard characters.count == 17 else { return nil }
        let codes = Array("ABCDEFGHJKLMNPRSTVWXY")
        guard let index = codes.firstIndex(of: characters[9]) else { return nil }
        return String(2010 + index)
    }
}

/// The charging inlets Teslas use in a region. The roster doesn't report the inlet, so the
/// region picks it: NACS in North America, Japan, South Korea and Taiwan, GB/T in mainland
/// China, and CCS2 with Type 2 AC elsewhere.
public enum SiriCarChargingPort: String, Sendable, CaseIterable {
    case nacsDC, nacsAC, ccs2, type2AC, gbtDC, gbtAC

    static func ports(forRegion regionCode: String?) -> [SiriCarChargingPort] {
        switch regionCode?.uppercased() {
        case "US", "CA", "MX", "PR", "JP", "KR", "TW": [.nacsDC, .nacsAC]
        case "CN": [.gbtDC, .gbtAC]
        default: [.ccs2, .type2AC]
        }
    }
}
