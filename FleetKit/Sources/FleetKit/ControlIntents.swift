import AppIntents

// Control intents map to backend-advertised action names via `runControl`.
// `FleetIntentService.runControl` validates the action against the live
// `controlActions()` list and throws a friendly error if unsupported.
//
// Confirmation policy: unlock, trunk, frunk, and charge-limit changes prompt
// for confirmation; lock, climate, and vent run immediately.

/// Shortcuts, App Shortcuts, and snippet button intent. Siri AI uses the Control Car tool.
public struct LockVehicleIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Lock Tesla"
    public static let description = IntentDescription(
        "Locks all doors on the user's car (or Tesla) immediately. Use when the user says \"lock my car\" or \"lock my Tesla\". Omit the vehicle parameter to lock the user's selected car.",
        searchKeywords: ["lock my car", "lock car", "lock doors", "lock vehicle", "lock Tesla"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account to lock. Optional; omit to lock the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Lock \(\.$vehicle)")
        } otherwise: {
            Summary("Lock my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Lock \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for locking a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Lock my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for locking the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(
                action: "door_lock",
                vin: resolved.vin,
                humanName: String(localized: "locking", bundle: .module, comment: "Action name used in vehicle command error messages for locking doors.")
            )
            let summary = String(
                localized: "Locked \(resolved.name).",
                bundle: .module,
                comment: "Siri confirmation after locking a vehicle."
            )
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "door_lock", summary: summary)
            log.success("locked \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts, App Shortcuts, and snippet button intent. Siri AI uses the Control Car tool.
public struct UnlockVehicleIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Unlock Tesla"
    public static let description = IntentDescription(
        "Unlocks the doors on the user's car (or Tesla) after asking the user for confirmation. Use when the user says \"unlock my car\" or \"unlock my Tesla\". Omit the vehicle parameter to unlock the user's selected car.",
        searchKeywords: ["unlock my car", "unlock car", "unlock doors", "unlock vehicle", "unlock Tesla"]
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account to unlock. Optional; omit to unlock the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Unlock \(\.$vehicle)")
        } otherwise: {
            Summary("Unlock my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Unlock \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for unlocking a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Unlock my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for unlocking the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await confirmWithSafetyGate(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Unlock \(resolved.name)?",
                        bundle: FleetKitLocalization.bundleDescription,
                        comment: "Confirmation prompt before unlocking a vehicle."
                    )
                )
            )
            try await service.runControl(
                action: "door_unlock",
                vin: resolved.vin,
                humanName: String(localized: "unlocking", bundle: .module, comment: "Action name used in vehicle command error messages for unlocking doors.")
            )
            let summary = String(
                localized: "Unlocked \(resolved.name).",
                bundle: .module,
                comment: "Siri confirmation after unlocking a vehicle."
            )
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "door_unlock", summary: summary)
            log.success("unlocked \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts, App Shortcuts, and snippet button intent. Siri AI uses Control Car or Set Car Temperature.
public struct StartClimateIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Start Car Climate"
    public static let description = IntentDescription(
        "Warms up, cools down, or preconditions the user's car or Tesla by starting cabin HVAC at its current setpoint. Use for requests like \"warm up my car\", \"cool down my car\", or \"warm up my Tesla\". Use Set Car Temperature for a target temperature, or Control Car for multi-setting prep.",
        searchKeywords: [
            "warm up", "warm up my car", "cool down", "cool down my car",
            "heat my car", "cool my car", "precondition", "precondition my car",
            "turn on AC", "turn on heat", "climate on", "start climate", "warm up my Tesla"
        ]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account to warm up, cool down, or precondition. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Warm up or start climate in \(\.$vehicle)")
        } otherwise: {
            Summary("Warm up my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Warm up \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for starting climate in a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Warm up my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for starting climate in the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: String(
                    localized: "Starting climate in \(resolved.name)",
                    bundle: .module,
                    comment: "Progress label while starting cabin climate."
                )
            ) {
                try await service.runControl(
                    action: "auto_conditioning_start",
                    vin: resolved.vin,
                    humanName: String(localized: "starting climate", bundle: .module, comment: "Action name used in vehicle command error messages for starting climate."),
                    allowAsyncWake: true
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: String(localized: "start climate", bundle: .module, comment: "Infinitive action phrase used in wake-up messages for starting climate."),
                confirmed: String(
                    localized: "Climate is starting in \(resolved.name).",
                    bundle: .module,
                    comment: "Siri confirmation after starting cabin climate."
                )
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "auto_conditioning_start",
                deliveryState: deliveryState,
                summary: summary
            )
            log.success("started climate in \(resolved.name) (\(deliveryState.rawValue))")
            return .result(
                value: result,
                dialog: IntentDialog(stringLiteral: summary),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: summary,
                    scope: scope,
                    running: true,
                    deliveryState: deliveryState
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts and App Shortcuts intent. Siri AI uses the Control Car tool.
public struct VentWindowsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Vent Tesla Windows"
    public static let description = IntentDescription(
        "Lowers all four of the car's windows a few centimeters to let hot air out of a parked Tesla. To roll the car's windows back up, use Close Tesla Windows (or Control Car).",
        searchKeywords: ["crack the windows", "vent", "let air out"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose windows should be vented. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Vent \(\.$vehicle) windows")
        } otherwise: {
            Summary("Vent my car windows")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Vent \(vehicle.name) windows",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for venting windows on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Vent my car windows",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for venting windows on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(
                action: "window_control",
                vin: resolved.vin,
                params: ["command": .string("vent")],
                humanName: String(localized: "venting the windows", bundle: .module, comment: "Action name used in vehicle command error messages for venting windows.")
            )
            let summary = String(
                localized: "Venting \(resolved.name)'s windows.",
                bundle: .module,
                comment: "Siri confirmation after venting vehicle windows."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "window_control",
                appliedValue: "vent",
                summary: summary
            )
            log.success("venting windows on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Which storage compartment to open.
public enum TrunkPosition: String, AppEnum, Sendable {
    case rear
    case front

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trunk")
    public static let caseDisplayRepresentations: [TrunkPosition: DisplayRepresentation] = [
        .rear: DisplayRepresentation(
            title: "Trunk",
            subtitle: "The rear cargo area at the back of the car",
            synonyms: ["rear trunk", "back trunk", "liftgate", "hatch", "boot"]
        ),
        .front: DisplayRepresentation(
            title: "Frunk",
            subtitle: "The front storage compartment under the hood",
            synonyms: ["front trunk", "hood", "bonnet"]
        )
    ]

    var spokenName: String {
        switch self {
        case .rear:
            String(localized: "trunk", bundle: .module, comment: "Spoken name for the rear trunk.")
        case .front:
            String(localized: "frunk", bundle: .module, comment: "Spoken name for the front trunk (frunk).")
        }
    }
}

/// Shortcuts and App Shortcuts intent. Siri AI uses the Control Car tool.
public struct OpenTrunkIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Open Tesla Trunk or Frunk"
    public static let description = IntentDescription(
        "Opens the car's rear trunk or its frunk (the front trunk under the hood), after asking the user to confirm. On cars with a powered liftgate, using it on an open rear trunk closes it. The frunk can't be closed remotely.",
        searchKeywords: ["trunk", "frunk", "front trunk", "rear trunk", "liftgate", "hatch", "boot", "hood"]
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla to open. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Trunk",
        description: "Frunk for the front trunk under the hood, or Trunk for the rear cargo area. \"Open the trunk\" means the rear trunk.",
        default: .rear
    )
    public var trunk: TrunkPosition

    public init() {}

    public init(vehicle: VehicleEntity? = nil, trunk: TrunkPosition) {
        self.vehicle = vehicle
        self.trunk = trunk
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Open \(\.$vehicle) \(\.$trunk)")
        } otherwise: {
            Summary("Open my car \(\.$trunk)")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$trunk)) { vehicle, trunk in
            let title: LocalizedStringResource = switch (vehicle, trunk) {
            case let (vehicle?, .rear):
                LocalizedStringResource(
                    "Open \(vehicle.name) trunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the rear trunk on a specific vehicle."
                )
            case let (vehicle?, .front):
                LocalizedStringResource(
                    "Open \(vehicle.name) frunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the frunk on a specific vehicle."
                )
            case (nil, .rear):
                LocalizedStringResource(
                    "Open my car trunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the rear trunk on the user's selected car."
                )
            case (nil, .front):
                LocalizedStringResource(
                    "Open my car frunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the frunk on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let result = try await Self.open(trunk, vehicle: vehicle) { dialog in
                try await confirmWithSafetyGate(dialog: dialog)
            }
            log.success("opened \(trunk.rawValue) on \(result.vehicleName)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: result.summary))
        } catch {
            throw log.failure(error)
        }
    }

    /// Shared by this tool and the Shortcuts-only Open Frunk intent.
    static func open(
        _ trunk: TrunkPosition,
        vehicle: VehicleEntity?,
        confirm: (IntentDialog) async throws -> Void
    ) async throws -> VehicleCommandResultEntity {
        let service = FleetIntentService.make()
        let resolved = try await service.resolvedVehicle(vehicle?.id)
        let confirmDialog = switch trunk {
        case .rear:
            IntentDialog(
                LocalizedStringResource(
                    "Open the trunk on \(resolved.name)?",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before opening the rear trunk."
                )
            )
        case .front:
            IntentDialog(
                LocalizedStringResource(
                    "Open the frunk on \(resolved.name)?",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before opening the front trunk (frunk)."
                )
            )
        }
        try await confirm(confirmDialog)
        let humanName = switch trunk {
        case .rear:
            String(localized: "opening the trunk", bundle: .module, comment: "Action name used in vehicle command error messages for opening the rear trunk.")
        case .front:
            String(localized: "opening the frunk", bundle: .module, comment: "Action name used in vehicle command error messages for opening the frunk.")
        }
        try await service.runControl(
            action: "actuate_trunk",
            vin: resolved.vin,
            params: ["which_trunk": .string(trunk.rawValue)],
            humanName: humanName
        )
        let summary = switch trunk {
        case .rear:
            String(localized: "Opening the trunk on \(resolved.name).", bundle: .module, comment: "Siri confirmation after opening the rear trunk.")
        case .front:
            String(localized: "Opening the frunk on \(resolved.name).", bundle: .module, comment: "Siri confirmation after opening the frunk.")
        }
        return VehicleCommandResultEntity(
            vehicle: resolved,
            action: "actuate_trunk",
            appliedValue: trunk.rawValue,
            summary: summary
        )
    }
}

/// Kept so saved shortcuts that open the frunk keep working. Not a Siri tool:
/// Siri AI uses Control Car; Shortcuts and App Shortcuts use Open Tesla Trunk or Frunk.
public struct OpenFrunkIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Open Tesla Frunk"
    public static let description = IntentDescription(
        "Opens the frunk, the front storage compartment under the hood, after asking the user to confirm. The frunk can't be closed remotely."
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla whose frunk to open. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Open \(\.$vehicle) frunk")
        } otherwise: {
            Summary("Open my car frunk")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Open \(vehicle.name) frunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the frunk on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Open my car frunk",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for opening the frunk on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let result = try await OpenTrunkIntent.open(.front, vehicle: vehicle) { dialog in
                try await confirmWithSafetyGate(dialog: dialog)
            }
            log.success("opened frunk on \(result.vehicleName)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: result.summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetChargeLimitIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Charge Limit"
    public static let description = IntentDescription(
        "Sets the maximum battery state-of-charge percentage (50% to 100%) at which charging stops on a Tesla vehicle, after user confirmation. Use 80% for typical daily driving or up to 100% before long road trips."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose charge limit should be updated. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Charge Limit %",
        description: "Target battery charge limit as an integer percentage from 50 to 100 (for example 80 for daily use or 100 for a road trip).",
        default: 80,
        inclusiveRange: (50, 100)
    )
    public var percent: Int

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Set \(\.$vehicle) charge limit to \(\.$percent)%")
        } otherwise: {
            Summary("Set my car charge limit to \(\.$percent)%")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$percent)) { vehicle, percent in
            let percentText = FleetKitFormatting.percent(percent)
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Set \(vehicle.name) charge limit to \(percentText)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting the battery charge limit on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Set my car charge limit to \(percentText)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting the battery charge limit on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let clampedPercent = min(max(percent, 50), 100)
            let percentText = FleetKitFormatting.percent(clampedPercent)
            try await confirmWithSafetyGate(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Set \(resolved.name)'s charge limit to \(percentText)?",
                        bundle: FleetKitLocalization.bundleDescription,
                        comment: "Confirmation prompt before changing the battery charge limit."
                    )
                )
            )
            try await service.runControl(
                action: "set_charge_limit",
                vin: resolved.vin,
                params: ["percent": .int(clampedPercent)],
                humanName: String(localized: "setting the charge limit", bundle: .module, comment: "Action name used in vehicle command error messages for setting the charge limit.")
            )
            let summary = String(
                localized: "Set \(resolved.name)'s charge limit to \(percentText).",
                bundle: .module,
                comment: "Siri confirmation after changing the battery charge limit."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_charge_limit",
                appliedValue: percentText,
                summary: summary
            )
            log.success("charge limit \(clampedPercent)% on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}
