import AppIntents
import Foundation

/// The steps one intent will send to a car, after dropping a redundant HVAC start.
struct CarControlPlan: Sendable {
    let steps: [CarControlStep]
    /// When HVAC was already running and the implicitly inserted `auto_conditioning_start`
    /// was dropped, the time that anchors why it is considered running. `nil` otherwise.
    let existingStartAnchor: Date?

    var skippedRedundantStart: Bool { existingStartAnchor != nil }

    /// Drops an implicit `auto_conditioning_start` prerequisite when recent telemetry or a
    /// climate receipt shows HVAC already running. An explicit `climateOn: true` is always sent.
    static func make(_ steps: [CarControlStep], service: FleetIntentService, vin: String) async -> CarControlPlan {
        guard steps.count > 1, steps.first?.isImplicitHVACStart == true,
              let anchor = await service.climateRunningAnchor(vin: vin) else {
            return CarControlPlan(steps: steps, existingStartAnchor: nil)
        }
        return CarControlPlan(steps: Array(steps.dropFirst()), existingStartAnchor: anchor)
    }
}

/// What happened when a `CarControlPlan` was sent.
struct CarControlRunOutcome: Sendable {
    struct Failure: Sendable {
        let step: CarControlStep
        let error: any Error
    }

    /// Steps the provider accepted, in the order they were sent.
    var accepted: [CarControlStep] = []
    /// The step that failed after at least one earlier step was accepted.
    var failure: Failure?
    /// Steps that were never sent because an earlier step failed.
    var notSent: [CarControlStep] = []
    /// `.wakingVehicle` only when a lone step went out before a sleeping car woke.
    var deliveryState: VehicleCommandDeliveryState = .confirmed

    var acceptedDetail: String { accepted.map(\.label).joined(separator: ", ") }

    /// A spoken summary that names what was applied, what failed, and what was not sent,
    /// or `nil` when every step was accepted.
    func partialFailureSummary(vehicleName: String) -> String? {
        guard let failure else { return nil }
        let acceptedList = accepted.map(\.label).joined(separator: ", ")
        // Error messages are usually full sentences; the summary supplies the period.
        var errorMessage = failure.error.localizedDescription
        if errorMessage.hasSuffix(".") { errorMessage.removeLast() }
        if notSent.isEmpty {
            return String(
                localized: "\(vehicleName) accepted: \(acceptedList). I couldn't confirm \(failure.step.label): \(errorMessage).",
                bundle: .module,
                comment: "Siri summary when a multi-step vehicle command partially succeeded and had no remaining skipped steps. Placeholders: vehicle name, accepted steps, failed step, error description."
            )
        }
        let notSentList = notSent.map(\.label).joined(separator: ", ")
        return String(
            localized: "\(vehicleName) accepted: \(acceptedList). I couldn't confirm \(failure.step.label): \(errorMessage). Not sent: \(notSentList).",
            bundle: .module,
            comment: "Siri summary when a multi-step vehicle command partially succeeded and skipped remaining steps. Placeholders: vehicle name, accepted steps, failed step, error description, skipped steps."
        )
    }
}

/// The one executor for multi-step car control intents (Control Car, Configure Cabin Climate,
/// Set Seat Heater).
///
/// Steps go out one at a time. Tesla vehicles process commands serially, so overlapping
/// requests can be rejected as busy, and settings such as Dog Mode and the cabin target would
/// otherwise land in an unpredictable order. A sequence also stops cleanly at the first
/// failure, so the user hears exactly which changes were applied and which were never sent.
enum CarControlStepRunner {
    /// Sends every step in `plan` in order.
    ///
    /// A lone step that is safe to deliver asynchronously (see `CarControlStep.isAsyncWakeEligible`)
    /// may go out with `wait_for_completion=false` when the car is asleep. Throws when the first
    /// step fails, because nothing was applied; later failures are returned in the outcome.
    static func run(_ plan: CarControlPlan, service: FleetIntentService, vin: String) async throws -> CarControlRunOutcome {
        if plan.steps.count == 1, let sole = plan.steps.first {
            let deliveryState = try await sole.run(
                service: service,
                vin: vin,
                allowAsyncWake: !plan.skippedRedundantStart && sole.isAsyncWakeEligible
            )
            return CarControlRunOutcome(accepted: [sole], deliveryState: deliveryState)
        }

        var outcome = CarControlRunOutcome()
        for (index, step) in plan.steps.enumerated() {
            try Task.checkCancellation()
            do {
                try await step.run(service: service, vin: vin)
                outcome.accepted.append(step)
            } catch {
                guard !outcome.accepted.isEmpty, !(error is CancellationError) else { throw error }
                outcome.failure = .init(step: step, error: error)
                outcome.notSent = Array(plan.steps[(index + 1)...])
                return outcome
            }
        }
        return outcome
    }
}

extension LongRunningIntent {
    /// Runs validated steps for the Control Car and Unlock or Open Car tools: checks that the
    /// provider offers every step, asks once to confirm the sensitive ones, sends the steps in
    /// order, and describes what the car accepted. A failure after the first accepted step
    /// comes back as a result that didn't succeed rather than an error.
    func runCarControl(
        _ steps: [CarControlStep],
        on vehicle: FleetVehicleInfo,
        action: String,
        service: FleetIntentService,
        log: FleetIntentLog
    ) async throws -> VehicleCommandResultEntity {
        let available = try await service.controlActions(for: vehicle)
        if let unavailable = steps.first(where: { !available.supports($0.action) }) {
            throw FleetKitError.unsupportedAction(unavailable.label)
        }
        let sensitive = steps.filter(\.needsConfirmation).map(\.label)
        if !sensitive.isEmpty {
            let description = sensitive.formatted(.list(type: .and))
            try await confirmWithSafetyGate(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Confirm these changes to \(vehicle.name): \(description)?",
                        bundle: FleetKitLocalization.bundleDescription,
                        comment: "Confirmation prompt listing sensitive vehicle control changes."
                    )
                )
            )
        }

        let plan = await CarControlPlan.make(steps, service: service, vin: vehicle.vin)
        let outcome = try await performSandboxAwareBackgroundTask(
            description: String(
                localized: "Controlling \(vehicle.name)",
                bundle: .module,
                comment: "Progress label while running one or more vehicle control commands."
            )
        ) {
            try await CarControlStepRunner.run(plan, service: service, vin: vehicle.vin)
        }

        let detail = outcome.acceptedDetail
        if let failure = outcome.failure, let summary = outcome.partialFailureSummary(vehicleName: vehicle.name) {
            _ = log.failure(failure.error)
            return VehicleCommandResultEntity(
                vehicle: vehicle,
                action: action,
                succeeded: false,
                appliedValue: detail,
                summary: summary
            )
        }
        let summary = outcome.deliveryState.summary(
            vehicleName: vehicle.name,
            wakingAction: String(localized: "apply: \(detail)", bundle: .module, comment: "Infinitive action phrase in wake-up message listing requested car controls."),
            confirmed: String(localized: "\(vehicle.name) accepted: \(detail).", bundle: .module, comment: "Siri confirmation listing vehicle controls accepted by the car.")
        )
        log.success("completed \(outcome.accepted.count) requested car controls (\(outcome.deliveryState.rawValue))")
        return VehicleCommandResultEntity(
            vehicle: vehicle,
            action: action,
            deliveryState: outcome.deliveryState,
            appliedValue: detail,
            summary: summary
        )
    }
}
