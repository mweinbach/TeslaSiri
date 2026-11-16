import AppIntents
import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// Answers questions about one or more live readings in a single call, such as
/// "what's my tire pressure and mileage?" or "how much range do I have and is it locked?".
@AppIntent(.tool)
public struct GetVehicleInfoIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Tesla Vehicle Info"
    public static let description = IntentDescription(
        "Reads live data from the user's car (or Tesla) and answers only what was asked: battery, range, tire pressure, mileage, charging, cabin climate, locks and open doors, or where the car is. Pass every topic the user asked about in one call. Returns the requested readings for follow-up questions.",
        searchKeywords: ["my car", "car battery", "battery", "range", "tire pressure", "PSI", "mileage", "odometer", "miles", "charging", "temperature", "locked", "is my car locked", "doors", "windows", "where is my car", "location"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The car to read. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Topics",
        description: "Every reading the user asked about, for example battery and tire pressure for \"what's my battery and tire pressure?\". Include each topic once.",
        requestValueDialog: IntentDialog("What would you like to know about your car?")
    )
    public var topics: [VehicleInfoTopic]

    public init() {}

    public init(vehicle: VehicleEntity? = nil, topics: [VehicleInfoTopic]) {
        self.vehicle = vehicle
        self.topics = topics
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Get \(\.$topics) for \(\.$vehicle)")
        } otherwise: {
            Summary("Get \(\.$topics) for my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$topics)) { vehicle, topics in
            let topicText = topics.map(\.spokenName).formatted(.list(type: .and))
            return DisplayRepresentation(
                title: VehicleEntity.predictionTitle(verb: "Get", vehicle: vehicle, suffix: topicText)
            )
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let requested = topics.isEmpty ? VehicleInfoTopic.allCases : topics
            let snapshot = try await service.snapshot(for: resolved, topics: requested)
            let address: String?
            let mapData: SiriRenderedMapData?
            if requested.contains(.location), let latitude = snapshot.latitude, let longitude = snapshot.longitude {
                let allowNetwork = FleetIntentService.testingOverride == nil
                async let place = allowNetwork ? FleetLocationNamer.address(latitude: latitude, longitude: longitude) : nil
                async let map = SiriMapSnapshotRenderer.renderLocationPin(
                    latitude: latitude,
                    longitude: longitude,
                    style: SiriSnippetStateStore.shared.mapStyle(for: "vehicle"),
                    accentHex: 0x0A84FF,
                    allowNetworkSnapshot: allowNetwork
                )
                (address, mapData) = await (place, map)
            } else {
                address = nil
                mapData = nil
            }

            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name, locationAddress: address)
            let answer = entity.spokenAnswer(for: requested)
            log.success("answered \(requested.map(\.rawValue).joined(separator: ",")) for \(resolved.name)")
            return .result(
                value: entity,
                dialog: IntentDialog("\(answer)"),
                view: VehicleStatusSnippetView(status: entity, mapData: mapData, topics: Set(requested))
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// A group of live readings the Get Tesla Vehicle Info tool can report.
public enum VehicleInfoTopic: String, AppEnum, CaseIterable, Sendable {
    case battery
    case range
    case charging
    case tirePressure
    case odometer
    case climate
    case security
    case location

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Vehicle Info Topic")
    public static let caseDisplayRepresentations: [VehicleInfoTopic: DisplayRepresentation] = [
        .battery: DisplayRepresentation(title: "Battery", subtitle: "Battery percent (state of charge)", image: .init(systemName: "battery.75percent")),
        .range: DisplayRepresentation(title: "Range", subtitle: "Estimated miles of driving left", image: .init(systemName: "road.lanes")),
        .charging: DisplayRepresentation(title: "Charging", subtitle: "Plugged in or not, charging speed, time to full, charge limit, and charge port", image: .init(systemName: "bolt.car")),
        .tirePressure: DisplayRepresentation(title: "Tire Pressure", subtitle: "PSI of each tire and any low tire", image: .init(systemName: "tirepressure")),
        .odometer: DisplayRepresentation(title: "Mileage", subtitle: "Odometer: total miles driven", image: .init(systemName: "gauge.with.dots.needle.33percent")),
        .climate: DisplayRepresentation(title: "Climate", subtitle: "Cabin and outside temperature, climate on or off, setpoint, seat and steering wheel heat, Dog Mode, defrost", image: .init(systemName: "thermometer.medium")),
        .security: DisplayRepresentation(title: "Locks & Security", subtitle: "Locked or unlocked, open doors, windows, trunk or frunk, and Sentry Mode", image: .init(systemName: "lock")),
        .location: DisplayRepresentation(title: "Location", subtitle: "Where the car is, and its speed if it's driving", image: .init(systemName: "location"))
    ]

    var spokenName: String {
        switch self {
        case .battery: "battery"
        case .range: "range"
        case .charging: "charging"
        case .tirePressure: "tire pressure"
        case .odometer: "mileage"
        case .climate: "climate"
        case .security: "locks"
        case .location: "location"
        }
    }
}

extension VehicleStatusEntity {
    /// Natural-language answer covering only the requested topics, in the order given.
    public func spokenAnswer(for topics: [VehicleInfoTopic], now: Date = .now) -> String {
        var seen = Set<VehicleInfoTopic>()
        let ordered = topics.filter { seen.insert($0).inserted }
        var sentences: [String] = []

        // Battery and range read naturally as one sentence when both are asked.
        if ordered.contains(.battery), ordered.contains(.range),
           let batteryPercent, let batteryRangeMiles {
            sentences.append("\(vehicleName) is at \(batteryPercent)% with about \(Int(batteryRangeMiles.rounded())) miles of range.")
            seen = [.battery, .range]
        } else {
            seen = []
        }

        for topic in ordered where !seen.contains(topic) {
            if let sentence = sentence(for: topic) {
                sentences.append(sentence)
            }
        }

        if let updatedAt, now.timeIntervalSince(updatedAt) > 60 * 60 {
            let age = updatedAt.formatted(.relative(presentation: .named))
            sentences.append("These readings are from \(age), while the car was asleep.")
        }

        return sentences.isEmpty
            ? "\(vehicleName) didn't report that information. Try again once the car is awake."
            : sentences.joined(separator: " ")
    }

    private func sentence(for topic: VehicleInfoTopic) -> String? {
        switch topic {
        case .battery:
            return batteryPercent.map { "\(vehicleName) is at \($0)% battery." }
        case .range:
            return batteryRangeMiles.map { "Estimated range is \(Int($0.rounded())) miles." }
        case .charging:
            return chargingSentence
        case .tirePressure:
            return tireSentence
        case .odometer:
            return odometerMiles.map { "The odometer reads \(Int($0.rounded()).formatted()) miles." }
        case .climate:
            return climateSentence
        case .security:
            return securitySentence
        case .location:
            return locationSentence
        }
    }

    private var chargingSentence: String? {
        guard let chargingState else { return nil }
        let limit = chargeLimitPercent.map { " The charge limit is \($0)%." } ?? ""
        switch chargingState.lowercased() {
        case "charging", "starting":
            var text = "It's charging"
            if let chargerPowerKW, chargerPowerKW > 0 {
                text += String(format: " at %.0f kW", chargerPowerKW)
            }
            if let chargeRateMPH, chargeRateMPH > 0 {
                text += ", adding about \(Int(chargeRateMPH.rounded())) miles of range per hour"
            }
            if let minutesToFullCharge {
                let duration = Duration.seconds(minutesToFullCharge * 60)
                    .formatted(.units(allowed: [.hours, .minutes], width: .wide))
                text += ", with \(duration) to go"
            }
            return text + "." + limit
        case "complete":
            return "Charging is complete." + limit
        case "stopped", "nopower":
            return "It's plugged in but not charging." + limit
        case "disconnected":
            let port = chargePortDoorOpen == true ? " The charge port door is open." : ""
            return "It's not plugged in." + limit + port
        default:
            return "Charging state: \(chargingState)." + limit
        }
    }

    private var tireSentence: String? {
        let tires: [(String, Double?)] = [
            ("front left", frontLeftTirePSI), ("front right", frontRightTirePSI),
            ("rear left", rearLeftTirePSI), ("rear right", rearRightTirePSI)
        ]
        let readings = tires.compactMap { name, psi in psi.map { (name, Int($0.rounded())) } }
        guard !readings.isEmpty else { return "There's no recent tire pressure reading. Tesla reports it after a short drive." }
        let list = readings.map { "\($0.0) \($0.1)" }.formatted(.list(type: .and))
        var text = "Tire pressures are \(list) PSI."
        let low = readings.filter { $0.1 < 38 }.map(\.0)
        if !low.isEmpty {
            text += " The \(low.formatted(.list(type: .and))) \(low.count == 1 ? "tire looks" : "tires look") low."
        }
        return text
    }

    private var climateSentence: String? {
        var parts: [String] = []
        let unit = temperatureUnit ?? "°"
        func degrees(_ value: Double) -> String { "\(Int(value.rounded()))\(unit)" }

        if let insideTemp, let outsideTemp {
            parts.append("It's \(degrees(insideTemp)) inside and \(degrees(outsideTemp)) outside.")
        } else if let insideTemp {
            parts.append("It's \(degrees(insideTemp)) inside.")
        } else if let outsideTemp {
            parts.append("It's \(degrees(outsideTemp)) outside.")
        }
        if let isClimateOn {
            if isClimateOn {
                parts.append("Climate is on" + (targetTemp.map { ", set to \(degrees($0))." } ?? "."))
            } else {
                parts.append("Climate is off.")
            }
        }
        if dogModeOn == true { parts.append("Dog Mode is on.") }
        if maxDefrostOn == true { parts.append("Max defrost is on.") }
        if let seatHeaterSummary, seatHeaterSummary.contains(where: { "123".contains($0) }) {
            parts.append("Seat heat: \(seatHeaterSummary).")
        }
        if steeringWheelHeaterOn == true { parts.append("The steering wheel heater is on.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var securitySentence: String? {
        var parts: [String] = []
        if let isLocked { parts.append(isLocked ? "It's locked" : "It's unlocked") }
        if let sentryModeOn { parts.append(sentryModeOn ? "Sentry Mode is on" : "Sentry Mode is off") }
        var text = parts.isEmpty ? "" : parts.joined(separator: " and ") + "."
        if let openClosures {
            text += openClosures == "None"
                ? " All doors, windows, the trunk, and the frunk are closed."
                : " Open: \(openClosures)."
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var locationSentence: String? {
        let place = locationAddress.map { "near \($0)" }
            ?? ((latitude != nil && longitude != nil) ? "at the location shown in the Wattie app" : nil)
        guard let place else { return "\(vehicleName) hasn't reported its location recently." }
        if let speedMPH, speedMPH > 0, gear == "D" || gear == "R" {
            return "\(vehicleName) is driving \(place) at \(Int(speedMPH.rounded())) mph."
        }
        return "\(vehicleName) is parked \(place)."
    }
}

/// Reverse-geocodes the car's coordinates for spoken answers. Uses MapKit, which
/// is available in the App Intents extension.
enum FleetLocationNamer {
    static func address(latitude: Double?, longitude: Double?) async -> String? {
        guard let latitude, let longitude,
              let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else {
            return nil
        }
        do {
            guard let item = try await request.mapItems.first else { return nil }
            let candidates = [item.address?.shortAddress, item.name, item.address?.fullAddress]
            return candidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        } catch {
            return nil
        }
    }
}
