import AppIntents
import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// Answers questions about one or more live readings in a single call, such as
/// "what's my tire pressure and mileage?" or "how much range do I have and is it locked?".
@AppIntent(.tool)
public struct GetVehicleInfoIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Vehicle Info"
    public static let description = IntentDescription(
        "Reads live data from the user's car (or Tesla) and answers only what was asked: battery, range, tire pressure, mileage, charging, cabin climate, locks and open doors, or where the car is. Pass every topic the user asked about in one call. Returns the requested readings for follow-up questions.",
        searchKeywords: ["my car", "Tesla", "car battery", "battery", "range", "tire pressure", "PSI", "mileage", "odometer", "miles", "charging", "temperature", "locked", "is my car locked", "doors", "windows", "where is my car", "location"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Get \(vehicle.name) \(topicText)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for reading specific telemetry topics on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Get my car \(topicText)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for reading specific telemetry topics on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let requested = topics.isEmpty ? VehicleInfoTopic.allCases : topics
            let snapshot = try await service.snapshot(for: resolved, topics: requested)
            let address: String?
            if requested.contains(.location), let latitude = snapshot.latitude, let longitude = snapshot.longitude {
                let allowNetwork = FleetIntentService.testingOverride == nil
                address = allowNetwork ? await FleetLocationNamer.address(latitude: latitude, longitude: longitude) : nil
            } else {
                address = nil
            }

            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name, locationAddress: address)
            let answer = entity.spokenAnswer(for: requested)
            log.success("answered \(requested.map(\.rawValue).joined(separator: ",")) for \(resolved.name)")
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: answer),
                snippetIntent: VehicleStatusSnippetIntent(status: entity, topics: requested)
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// A group of live readings the Get Vehicle Info tool can report.
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
        case .battery:
            String(localized: "battery", bundle: .module, comment: "Spoken topic name for battery level.")
        case .range:
            String(localized: "range", bundle: .module, comment: "Spoken topic name for driving range.")
        case .charging:
            String(localized: "charging", bundle: .module, comment: "Spoken topic name for charging status.")
        case .tirePressure:
            String(localized: "tire pressure", bundle: .module, comment: "Spoken topic name for tire pressure.")
        case .odometer:
            String(localized: "mileage", bundle: .module, comment: "Spoken topic name for odometer mileage.")
        case .climate:
            String(localized: "climate", bundle: .module, comment: "Spoken topic name for cabin climate.")
        case .security:
            String(localized: "locks", bundle: .module, comment: "Spoken topic name for door locks and security.")
        case .location:
            String(localized: "location", bundle: .module, comment: "Spoken topic name for vehicle location.")
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
            let percentText = FleetKitFormatting.percent(batteryPercent)
            let rangeText = FleetKitFormatting.distance(miles: batteryRangeMiles, usesMetric: usesMetric, width: .wide, fractionLength: 0)
            sentences.append(
                String(
                    localized: "\(vehicleName) is at \(percentText) with about \(rangeText) of range.",
                    bundle: .module,
                    comment: "Spoken vehicle status sentence combining battery percentage and estimated range."
                )
            )
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
            sentences.append(
                String(
                    localized: "These readings are from \(age), while the car was asleep.",
                    bundle: .module,
                    comment: "Spoken note explaining that vehicle telemetry is older than an hour because the car is asleep."
                )
            )
        }

        return sentences.isEmpty
            ? String(
                localized: "\(vehicleName) didn't report that information. Try again once the car is awake.",
                bundle: .module,
                comment: "Spoken fallback when requested telemetry fields are unavailable."
            )
            : sentences.joined(separator: " ")
    }

    private func sentence(for topic: VehicleInfoTopic) -> String? {
        switch topic {
        case .battery:
            return batteryPercent.map {
                let percentText = FleetKitFormatting.percent($0)
                return String(
                    localized: "\(vehicleName) is at \(percentText) battery.",
                    bundle: .module,
                    comment: "Spoken sentence reporting battery percentage."
                )
            }
        case .range:
            return batteryRangeMiles.map {
                let rangeText = FleetKitFormatting.distance(miles: $0, usesMetric: usesMetric, width: .wide, fractionLength: 0)
                return String(
                    localized: "Estimated range is \(rangeText).",
                    bundle: .module,
                    comment: "Spoken sentence reporting estimated driving range."
                )
            }
        case .charging:
            return chargingSentence
        case .tirePressure:
            return tireSentence
        case .odometer:
            return odometerMiles.map {
                let distanceText = FleetKitFormatting.distance(miles: $0, usesMetric: usesMetric, width: .wide, fractionLength: 0)
                return String(
                    localized: "The odometer reads \(distanceText).",
                    bundle: .module,
                    comment: "Spoken sentence reporting vehicle odometer reading."
                )
            }
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
        let limitSentence = chargeLimitPercent.map { percent -> String in
            let percentText = FleetKitFormatting.percent(percent)
            return String(
                localized: "The charge limit is \(percentText).",
                bundle: .module,
                comment: "Spoken sentence reporting the battery charge limit."
            )
        }
        var sentences: [String] = []
        switch chargingState.lowercased() {
        case "charging", "starting":
            var clauses: [String] = []
            if let chargerPowerKW, chargerPowerKW > 0 {
                let powerText = FleetKitFormatting.powerKW(chargerPowerKW, fractionLength: 0)
                clauses.append(
                    String(
                        localized: "It's charging at \(powerText)",
                        bundle: .module,
                        comment: "Opening clause of spoken charging sentence including power in kW."
                    )
                )
            } else {
                clauses.append(
                    String(
                        localized: "It's charging",
                        bundle: .module,
                        comment: "Opening clause of spoken charging sentence when power is unavailable."
                    )
                )
            }
            if let chargeRateMPH, chargeRateMPH > 0 {
                let rateDistance = FleetKitFormatting.distance(miles: chargeRateMPH, usesMetric: usesMetric, width: .wide, fractionLength: 0)
                clauses.append(
                    String(
                        localized: "adding about \(rateDistance) of range per hour",
                        bundle: .module,
                        comment: "Clause of spoken charging sentence reporting range added per hour."
                    )
                )
            }
            if let minutesToFullCharge {
                let duration = FleetKitFormatting.durationMinutes(minutesToFullCharge, width: .wide)
                clauses.append(
                    String(
                        localized: "with \(duration) to go",
                        bundle: .module,
                        comment: "Clause of spoken charging sentence reporting remaining charge time."
                    )
                )
            }
            sentences.append(clauses.joined(separator: ", ") + ".")
        case "complete":
            sentences.append(String(localized: "Charging is complete.", bundle: .module, comment: "Spoken sentence when battery charging is finished."))
        case "stopped", "nopower":
            sentences.append(String(localized: "It's plugged in but not charging.", bundle: .module, comment: "Spoken sentence when the car is plugged in but not actively charging."))
        case "disconnected":
            sentences.append(String(localized: "It's not plugged in.", bundle: .module, comment: "Spoken sentence when no charging cable is connected."))
        default:
            let localizedState = VehicleStatusEntity.localizedChargingState(chargingState)
            sentences.append(
                String(
                    localized: "Charging state: \(localizedState).",
                    bundle: .module,
                    comment: "Spoken fallback sentence for an unrecognized charging state."
                )
            )
        }
        if let limitSentence {
            sentences.append(limitSentence)
        }
        if chargingState.lowercased() == "disconnected", chargePortDoorOpen == true {
            sentences.append(
                String(
                    localized: "The charge port door is open.",
                    bundle: .module,
                    comment: "Spoken sentence noting that the charge port door is open while unplugged."
                )
            )
        }
        return sentences.joined(separator: " ")
    }

    private var tireSentence: String? {
        let tires: [(String, Double?)] = [
            (String(localized: "front left", bundle: .module, comment: "Front left tire position."), frontLeftTirePSI),
            (String(localized: "front right", bundle: .module, comment: "Front right tire position."), frontRightTirePSI),
            (String(localized: "rear left", bundle: .module, comment: "Rear left tire position."), rearLeftTirePSI),
            (String(localized: "rear right", bundle: .module, comment: "Rear right tire position."), rearRightTirePSI)
        ]
        let readings = tires.compactMap { name, psi in psi.map { (name, $0) } }
        guard !readings.isEmpty else {
            return String(
                localized: "There's no recent tire pressure reading. Tesla reports it after a short drive.",
                bundle: .module,
                comment: "Spoken answer when tire pressure readings are unavailable."
            )
        }
        let text: String
        if usesMetric {
            let list = readings.map { name, psi in
                let pressure = FleetKitFormatting.tirePressure(psi: psi, usesMetric: true)
                return String(localized: "\(name) \(pressure)", bundle: .module, comment: "Tire position paired with its metric pressure reading.")
            }.formatted(.list(type: .and))
            text = String(
                localized: "Tire pressures are \(list).",
                bundle: .module,
                comment: "Spoken sentence listing all four tire pressures in metric units."
            )
        } else {
            let list = readings.map { name, psi in
                "\(name) \(Int(psi.rounded()))"
            }.formatted(.list(type: .and))
            text = String(
                localized: "Tire pressures are \(list) PSI.",
                bundle: .module,
                comment: "Spoken sentence listing all four tire pressures in PSI."
            )
        }
        let low = readings.filter { Int($0.1.rounded()) < 38 }.map(\.0)
        guard !low.isEmpty else { return text }
        let lowList = low.formatted(.list(type: .and))
        let warning = low.count == 1
            ? String(localized: "The \(lowList) tire looks low.", bundle: .module, comment: "Spoken warning when a single tire has low pressure.")
            : String(localized: "The \(lowList) tires look low.", bundle: .module, comment: "Spoken warning when multiple tires have low pressure.")
        return "\(text) \(warning)"
    }

    private var climateSentence: String? {
        var parts: [String] = []
        let inFahrenheit = temperatureUnit != "°C"
        func degrees(_ value: Double) -> String {
            FleetKitFormatting.temperature(value, inFahrenheit: inFahrenheit, fractionLength: 0)
        }

        if let insideTemp, let outsideTemp {
            let insideText = degrees(insideTemp)
            let outsideText = degrees(outsideTemp)
            parts.append(
                String(
                    localized: "It's \(insideText) inside and \(outsideText) outside.",
                    bundle: .module,
                    comment: "Spoken sentence reporting both cabin and exterior temperatures."
                )
            )
        } else if let insideTemp {
            let insideText = degrees(insideTemp)
            parts.append(
                String(
                    localized: "It's \(insideText) inside.",
                    bundle: .module,
                    comment: "Spoken sentence reporting cabin temperature."
                )
            )
        } else if let outsideTemp {
            let outsideText = degrees(outsideTemp)
            parts.append(
                String(
                    localized: "It's \(outsideText) outside.",
                    bundle: .module,
                    comment: "Spoken sentence reporting exterior temperature."
                )
            )
        }
        if let isClimateOn {
            if isClimateOn {
                if let targetTemp {
                    let targetText = degrees(targetTemp)
                    parts.append(
                        String(
                            localized: "Climate is on, set to \(targetText).",
                            bundle: .module,
                            comment: "Spoken sentence reporting that climate control is on with a target temperature."
                        )
                    )
                } else {
                    parts.append(
                        String(
                            localized: "Climate is on.",
                            bundle: .module,
                            comment: "Spoken sentence reporting that climate control is on."
                        )
                    )
                }
            } else {
                parts.append(
                    String(
                        localized: "Climate is off.",
                        bundle: .module,
                        comment: "Spoken sentence reporting that climate control is off."
                    )
                )
            }
        }
        if dogModeOn == true {
            parts.append(String(localized: "Dog Mode is on.", bundle: .module, comment: "Spoken sentence reporting that Dog Mode is active."))
        }
        if maxDefrostOn == true {
            parts.append(String(localized: "Max defrost is on.", bundle: .module, comment: "Spoken sentence reporting that max defrost is active."))
        }
        if let seatHeaterSummary, seatHeaterSummary.contains(where: { "123".contains($0) }) {
            parts.append(
                String(
                    localized: "Seat heat: \(seatHeaterSummary).",
                    bundle: .module,
                    comment: "Spoken sentence summarizing active seat heater levels."
                )
            )
        }
        if steeringWheelHeaterOn == true {
            parts.append(
                String(
                    localized: "The steering wheel heater is on.",
                    bundle: .module,
                    comment: "Spoken sentence reporting that the heated steering wheel is active."
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var securitySentence: String? {
        var sentences: [String] = []
        switch (isLocked, sentryModeOn) {
        case (true, true):
            sentences.append(String(localized: "It's locked and Sentry Mode is on.", bundle: .module, comment: "Spoken security sentence when doors are locked and Sentry Mode is on."))
        case (true, false):
            sentences.append(String(localized: "It's locked and Sentry Mode is off.", bundle: .module, comment: "Spoken security sentence when doors are locked and Sentry Mode is off."))
        case (false, true):
            sentences.append(String(localized: "It's unlocked and Sentry Mode is on.", bundle: .module, comment: "Spoken security sentence when doors are unlocked and Sentry Mode is on."))
        case (false, false):
            sentences.append(String(localized: "It's unlocked and Sentry Mode is off.", bundle: .module, comment: "Spoken security sentence when doors are unlocked and Sentry Mode is off."))
        case (true, nil):
            sentences.append(String(localized: "It's locked.", bundle: .module, comment: "Spoken security sentence when doors are locked."))
        case (false, nil):
            sentences.append(String(localized: "It's unlocked.", bundle: .module, comment: "Spoken security sentence when doors are unlocked."))
        case (nil, true):
            sentences.append(String(localized: "Sentry Mode is on.", bundle: .module, comment: "Spoken security sentence when Sentry Mode is on."))
        case (nil, false):
            sentences.append(String(localized: "Sentry Mode is off.", bundle: .module, comment: "Spoken security sentence when Sentry Mode is off."))
        case (nil, nil):
            break
        }
        if let openClosures {
            if openClosures == "None" {
                sentences.append(
                    String(
                        localized: "All doors, windows, the trunk, and the frunk are closed.",
                        bundle: .module,
                        comment: "Spoken security sentence when no doors, windows, trunk, or frunk are open."
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "Open: \(openClosures).",
                        bundle: .module,
                        comment: "Spoken security sentence listing open doors, windows, trunk, or frunk."
                    )
                )
            }
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private var locationSentence: String? {
        let isDriving = (speedMPH ?? 0) > 0 && (gear == "D" || gear == "R")
        if let locationAddress {
            if isDriving, let speedMPH {
                let speedText = FleetKitFormatting.speed(mph: speedMPH, usesMetric: usesMetric, fractionLength: 0)
                return String(
                    localized: "\(vehicleName) is driving near \(locationAddress) at \(speedText).",
                    bundle: .module,
                    comment: "Spoken location sentence when the vehicle is driving near a named address."
                )
            }
            return String(
                localized: "\(vehicleName) is parked near \(locationAddress).",
                bundle: .module,
                comment: "Spoken location sentence when the vehicle is parked near a named address."
            )
        }
        if latitude != nil && longitude != nil {
            if isDriving, let speedMPH {
                let speedText = FleetKitFormatting.speed(mph: speedMPH, usesMetric: usesMetric, fractionLength: 0)
                return String(
                    localized: "\(vehicleName) is driving at \(speedText), at the location shown in the Wattie app.",
                    bundle: .module,
                    comment: "Spoken location sentence when driving with coordinates but no street address."
                )
            }
            return String(
                localized: "\(vehicleName) is parked at the location shown in the Wattie app.",
                bundle: .module,
                comment: "Spoken location sentence when parked with coordinates but no street address."
            )
        }
        return String(
            localized: "\(vehicleName) hasn't reported its location recently.",
            bundle: .module,
            comment: "Spoken location sentence when the vehicle has no recent coordinates."
        )
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
