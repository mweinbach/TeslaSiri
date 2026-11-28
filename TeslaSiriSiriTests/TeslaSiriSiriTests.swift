#if canImport(SiriEvaluations)
import SiriEvaluations
import Testing

struct WattieSiriEvaluation: Evaluation {
    let name: String
    let dataset: SiriScenarioLoader

    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await SiriService.run(scenario: sample)
    }

    var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}

@Suite("Wattie - Siri Evaluations", .serialized)
struct WattieSiriEvaluationTests {
    static let appDefinitions = IntentDefinitions(bundleIdentifier: "com.maxweinbach.TeslaSiri")

    // MARK: - Tool Intents
    static let ListCarsIntent = appDefinitions.intents["ListCarsIntent"]
    static let GetVehicleInfoIntent = appDefinitions.intents["GetVehicleInfoIntent"]
    static let GetVehicleStatusIntent = appDefinitions.intents["GetVehicleStatusIntent"]
    static let LocateCarIntent = appDefinitions.intents["LocateCarIntent"]
    static let ControlCarIntent = appDefinitions.intents["ControlCarIntent"]
    static let UnlockOrOpenCarIntent = appDefinitions.intents["UnlockOrOpenCarIntent"]
    static let SetCabinTemperatureIntent = appDefinitions.intents["SetCabinTemperatureIntent"]
    static let SetSeatClimateIntent = appDefinitions.intents["SetSeatClimateIntent"]
    static let SendNavigationIntent = appDefinitions.intents["SendNavigationIntent"]
    static let InstallSoftwareUpdateIntent = appDefinitions.intents["InstallSoftwareUpdateIntent"]
    static let CancelSoftwareUpdateIntent = appDefinitions.intents["CancelSoftwareUpdateIntent"]
    static let FindDrivesIntent = appDefinitions.intents["FindDrivesIntent"]
    static let GetDriveDetailsIntent = appDefinitions.intents["GetDriveDetailsIntent"]
    static let GetDrivingStatsIntent = appDefinitions.intents["GetDrivingStatsIntent"]
    static let GetRecentChargesIntent = appDefinitions.intents["GetRecentChargesIntent"]
    static let GetChargeDetailsIntent = appDefinitions.intents["GetChargeDetailsIntent"]
    static let GetChargingStatsIntent = appDefinitions.intents["GetChargingStatsIntent"]
    static let GetBatteryHealthIntent = appDefinitions.intents["GetBatteryHealthIntent"]
    static let GetSoftwareStatusIntent = appDefinitions.intents["GetSoftwareStatusIntent"]
    static let GetReleaseNotesIntent = appDefinitions.intents["GetReleaseNotesIntent"]

    // MARK: - App Skills
    static let VehicleControlSkill = appDefinitions.skills["vehicle-control"]
    static let PrepareTripSkill = appDefinitions.skills["prepare-trip"]
    static let OvernightSecuritySkill = appDefinitions.skills["overnight-security-check"]
    static let DrivingAndEnergySkill = appDefinitions.skills["driving-and-energy-insights"]
    static let SoftwareUpdateSkill = appDefinitions.skills["software-update-advisor"]

    // MARK: - Skill Loading & Core Routing Scenarios

    static let everydayInfoAndWarmup = SiriScenario {
        UserTurn("In Wattie, is my car locked and how much range is left?") {
            Loads(.required) { VehicleControlSkill }
            Calls { GetVehicleInfoIntent }
            Calls(.disallowed) { LocateCarIntent; UnlockOrOpenCarIntent }
        }
    }

    static let locateCarRoutesToLocateTool = SiriScenario {
        UserTurn("In Wattie, where did I park my car?") {
            Loads(.required) { VehicleControlSkill }
            Calls { LocateCarIntent }
            Calls(.disallowed) { GetVehicleInfoIntent; GetVehicleStatusIntent }
        }
    }

    static let controlCarWarmUp = SiriScenario {
        UserTurn("In Wattie, warm up my car and lock the doors") {
            Loads(.required) { VehicleControlSkill }
            Calls { ControlCarIntent }
            Calls(.disallowed) { UnlockOrOpenCarIntent; SetCabinTemperatureIntent }
        }
    }

    static let standaloneTemperatureCard = SiriScenario {
        UserTurn("In Wattie, set my car to 72 degrees") {
            Loads(.required) { VehicleControlSkill }
            Calls { SetCabinTemperatureIntent }
            Calls(.disallowed) { UnlockOrOpenCarIntent }
        }
    }

    static let unlockAndOpenRoutesToAuthenticatedTool = SiriScenario {
        UserTurn("In Wattie, unlock my car and pop the trunk") {
            Loads(.required) { VehicleControlSkill }
            Calls { UnlockOrOpenCarIntent }
            Calls(.disallowed) { ControlCarIntent }
        }
    }

    static let prepareTripWorkflow = SiriScenario {
        UserTurn("In Wattie, get my car ready for my commute to work") {
            Loads(.required) { PrepareTripSkill }
            Calls { GetVehicleInfoIntent }
            Calls(.disallowed) { UnlockOrOpenCarIntent }
        }
    }

    static let overnightSecurityWorkflow = SiriScenario {
        UserTurn("In Wattie, do an overnight security check on my car") {
            Loads(.required) { OvernightSecuritySkill }
            Calls { GetVehicleInfoIntent }
            Calls(.disallowed) { UnlockOrOpenCarIntent }
        }
    }

    static let drivingInsightsWorkflow = SiriScenario {
        UserTurn("In Wattie, how much did I drive this week and what was my efficiency?") {
            Loads(.required) { DrivingAndEnergySkill }
            Calls { GetDrivingStatsIntent }
            Calls(.disallowed) { ControlCarIntent; UnlockOrOpenCarIntent }
        }
    }

    static let softwareUpdateWorkflow = SiriScenario {
        UserTurn("In Wattie, does my car have a software update and what's new?") {
            Loads(.required) { SoftwareUpdateSkill }
            Calls {
                GetSoftwareStatusIntent
                GetReleaseNotesIntent
            }
            Calls(.disallowed) { InstallSoftwareUpdateIntent; CancelSoftwareUpdateIntent }
        }
    }

    // MARK: - Evaluations

    static let vehicleControlEvaluation = WattieSiriEvaluation(
        name: "Wattie - Vehicle control and live status",
        dataset: SiriScenarioLoader {
            everydayInfoAndWarmup
            locateCarRoutesToLocateTool
            controlCarWarmUp
            standaloneTemperatureCard
            unlockAndOpenRoutesToAuthenticatedTool
        }
    )

    @Test("Siri routes everyday reads and controls using the vehicle-control skill", .evaluates(vehicleControlEvaluation))
    func routesVehicleControl() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
        #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1.0)
    }

    static let workflowSkillsEvaluation = WattieSiriEvaluation(
        name: "Wattie - Multi-step workflow skills",
        dataset: SiriScenarioLoader {
            prepareTripWorkflow
            overnightSecurityWorkflow
            drivingInsightsWorkflow
            softwareUpdateWorkflow
        }
    )

    @Test("Siri loads all four specialist workflow skills and calls the expected tools", .evaluates(workflowSkillsEvaluation))
    func loadsWorkflowSkills() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
        #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1.0)
    }
}
#endif
