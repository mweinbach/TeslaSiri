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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check \(vehicle.name) battery",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking battery level on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check my car battery",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking battery level on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)

            let isCharging = snapshot.chargingState?.lowercased() == "charging"
            let dialogText: String
            switch (entity.batteryPercent, entity.batteryRangeMiles, isCharging) {
            case let (percent?, range?, true):
                let percentText = FleetKitFormatting.percent(percent)
                let rangeText = FleetKitFormatting.distance(miles: range, usesMetric: entity.usesMetric, fractionLength: 0)
                dialogText = String(
                    localized: "\(resolved.name) is at \(percentText) (\(rangeText) range) and charging.",
                    bundle: .module,
                    comment: "Siri battery readout with percentage, range, and active charging."
                )
            case let (percent?, range?, false):
                let percentText = FleetKitFormatting.percent(percent)
                let rangeText = FleetKitFormatting.distance(miles: range, usesMetric: entity.usesMetric, fractionLength: 0)
                dialogText = String(
                    localized: "\(resolved.name) is at \(percentText) (\(rangeText) range).",
                    bundle: .module,
                    comment: "Siri battery readout with percentage and range."
                )
            case let (percent?, nil, true):
                let percentText = FleetKitFormatting.percent(percent)
                dialogText = String(
                    localized: "\(resolved.name) is at \(percentText) and charging.",
                    bundle: .module,
                    comment: "Siri battery readout with percentage and active charging."
                )
            case let (percent?, nil, false):
                let percentText = FleetKitFormatting.percent(percent)
                dialogText = String(
                    localized: "\(resolved.name) is at \(percentText).",
                    bundle: .module,
                    comment: "Siri battery readout with percentage only."
                )
            case (nil, _, true):
                dialogText = String(
                    localized: "\(resolved.name) is charging at an unknown battery level.",
                    bundle: .module,
                    comment: "Siri battery readout when charging but percentage is unavailable."
                )
            case (nil, _, false):
                dialogText = String(
                    localized: "\(resolved.name) is at an unknown battery level.",
                    bundle: .module,
                    comment: "Siri battery readout when percentage is unavailable."
                )
            }
            log.success(dialogText)
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: dialogText)
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check \(vehicle.name) mileage",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking mileage on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check my car mileage",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking mileage on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)
            let dialogText: String
            if let mileage = entity.odometerDisplay {
                dialogText = String(
                    localized: "\(resolved.name)'s odometer is \(mileage).",
                    bundle: .module,
                    comment: "Siri readout for vehicle odometer distance."
                )
            } else {
                dialogText = String(
                    localized: "\(resolved.name)'s odometer reading is unavailable.",
                    bundle: .module,
                    comment: "Siri fallback when vehicle odometer distance is unavailable."
                )
            }
            log.success(dialogText)
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: dialogText)
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check \(vehicle.name) tire pressure",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking tire pressure on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check my car tire pressure",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking tire pressure on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let snapshot = try await service.snapshot(vin: resolved.vin)
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name)
            let dialogText: String
            if let tires = entity.tireSummary {
                dialogText = String(
                    localized: "\(resolved.name)'s tire pressure: \(tires).",
                    bundle: .module,
                    comment: "Siri readout for vehicle tire pressures."
                )
            } else {
                dialogText = String(
                    localized: "\(resolved.name) has no recent tire pressure reading.",
                    bundle: .module,
                    comment: "Siri fallback when tire pressure readings are unavailable."
                )
            }
            log.success(dialogText)
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: dialogText)
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check \(vehicle.name) status",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking status of a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check my car status",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking status of the user's selected car."
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
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Here's the latest on \(resolved.name).",
                        bundle: FleetKitLocalization.bundleDescription,
                        comment: "Short spoken introduction when presenting a vehicle status card."
                    )
                ),
                snippetIntent: VehicleStatusSnippetIntent(status: entity, topics: VehicleInfoTopic.allCases)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
