import AppIntents
import SwiftUI

/// Reads the current battery level, estimated range, and charging state and reports it as structured status plus spoken dialog.
/// Shortcuts and App Shortcuts only. Siri uses the Get Vehicle Info tool, which
/// covers this reading alongside any others in one call.
public struct GetBatteryLevelIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Check Battery Level"
    public static let description = IntentDescription(
        "Checks a Tesla vehicle's current battery percentage, estimated driving range in miles, charge limit, and active charging status. Omit the vehicle parameter to inspect the user's selected car."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account to inspect. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check \(\.$vehicle) battery")
        } otherwise: {
            Summary("Check my car battery")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Check", vehicle: vehicle, suffix: "battery"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)

            let battery = entity.batteryPercent.map { "\($0)%" } ?? "an unknown level"
            let range = entity.batteryRangeMiles.map { " (\(Int($0.rounded())) mi range)" } ?? ""
            let charging = (snapshot.chargingState?.lowercased() == "charging") ? " and charging" : ""
            log.success("\(resolved.name) at \(battery)\(range)\(charging)")
            return .result(
                value: entity,
                dialog: IntentDialog("\(resolved.name) is at \(battery)\(range)\(charging).")
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Reads the vehicle odometer/mileage from the latest live snapshot.
/// Shortcuts and App Shortcuts only. Siri uses the Get Vehicle Info tool, which
/// covers this reading alongside any others in one call.
public struct GetVehicleMileageIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Check Vehicle Mileage"
    public static let description = IntentDescription(
        "Reads a Tesla vehicle's total odometer mileage in miles from the latest live telemetry snapshot. Omit the vehicle parameter to inspect the user's selected car."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account to inspect. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check \(\.$vehicle) mileage")
        } otherwise: {
            Summary("Check my car mileage")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Check", vehicle: vehicle, suffix: "mileage"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)
            let mileage = entity.odometerDisplay ?? "unknown mileage"
            log.success("\(resolved.name) odometer \(mileage)")
            return .result(
                value: entity,
                dialog: IntentDialog("\(resolved.name)'s odometer is \(mileage).")
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Reads current TPMS PSI values from the latest live snapshot.
/// Shortcuts and App Shortcuts only. Siri uses the Get Vehicle Info tool, which
/// covers this reading alongside any others in one call.
public struct GetTirePressureIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Check Tire Pressure"
    public static let description = IntentDescription(
        "Checks a Tesla vehicle's tire pressure monitoring system (TPMS) readings in PSI for front-left, front-right, rear-left, and rear-right tires. Omit the vehicle parameter to inspect the user's selected car."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account to inspect. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check \(\.$vehicle) tire pressure")
        } otherwise: {
            Summary("Check my car tire pressure")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Check", vehicle: vehicle, suffix: "tire pressure"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)
            let tires = entity.tireSummary ?? "no recent tire pressure reading"
            log.success("\(resolved.name) tires: \(tires)")
            return .result(
                value: entity,
                dialog: IntentDialog("\(resolved.name)'s tire pressure: \(tires).")
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shows a full vehicle status snippet plus structured telemetry and a short supporting dialog.
@AppIntent(.tool)
public struct GetVehicleStatusIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Check Vehicle Status"
    public static let description = IntentDescription(
        "Shows a card with the user's car (or Tesla) at a glance: battery, range, charging, locks, climate, mileage, and tire pressure. Use for broad requests like \"check my car\", \"how's my car?\", or \"show my Tesla\". For specific readings, use the Get Vehicle Info tool, which answers only what was asked.",
        searchKeywords: ["check my car", "how is my car", "car status", "my car", "vehicle status", "Tesla status"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account to inspect. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check \(\.$vehicle) status")
        } otherwise: {
            Summary("Check my car status")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Check", vehicle: vehicle, suffix: "status"))
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let allowNetwork = FleetIntentService.testingOverride == nil

            let address: String? = allowNetwork
                ? await FleetLocationNamer.address(latitude: snapshot.latitude, longitude: snapshot.longitude)
                : nil
            let entity = VehicleStatusEntity(
                snapshot: snapshot,
                vehicleName: resolved.name,
                locationAddress: address
            )

            log.success("status snippet for \(resolved.name)")
            return .result(
                value: entity,
                dialog: IntentDialog("Here's the latest on \(resolved.name)."),
                snippetIntent: VehicleStatusSnippetIntent(status: entity, topics: VehicleInfoTopic.allCases)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
