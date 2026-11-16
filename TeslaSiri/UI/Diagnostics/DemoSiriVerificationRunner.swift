import AppIntents
import FleetKit
import Foundation
import Observation

struct SiriVerificationStepResult: Identifiable, Sendable {
    enum Category: String, Sendable {
        case skill = "Skill Workflow"
        case tool = "Siri Tool"
        case shortcut = "App Shortcut & Indexing"
    }

    let id = UUID()
    let category: Category
    let title: String
    let passed: Bool
    let detail: String
    let durationMS: Int
}

@MainActor
@Observable
final class DemoSiriVerificationRunner {
    static let shared = DemoSiriVerificationRunner()

    private(set) var isRunning = false
    private(set) var results: [SiriVerificationStepResult] = []
    private(set) var lastCompletedAt: Date?
    private(set) var totalConfirmationsRecorded = 0

    var passedCount: Int {
        results.filter(\.passed).count
    }

    var failedCount: Int {
        results.filter { !$0.passed }.count
    }

    func runAllOnDemoCar(sandbox: FleetSandboxStore = .shared) async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        totalConfirmationsRecorded = 0

        let confirmationBox = ConfirmationPromptBox()
        sandbox.setMode(.demoVehicle)
        sandbox.clearCommandLog()

        print("[SiriVerify] === STARTING ON-DEVICE DEMO CAR SIRI VERIFICATION ===")

        await FleetIntentService.$sandboxConfirmationRecorder.withValue({ prompt in
            confirmationBox.record(prompt)
        }) {
            // MARK: - Bundled Siri AI workflow scenarios

            await recordStep(.skill, "Skill: prepare-trip (Freezing Morning)") {
                sandbox.applyPreset(.freezingMorning)
                let info = try Self.unwrap(
                    try await GetVehicleInfoIntent(topics: [.battery, .range, .charging, .tirePressure, .climate]).perform().value,
                    "GetVehicleInfoIntent"
                )
                try Self.expect(info.insideTemp == 26.0 && info.outsideTemp == 22.0, "Expected 26°F inside / 22°F outside")
                try Self.expect(info.frontRightTirePSI == 36.5, "Expected low FR tire 36.5 PSI")

                let climate = ConfigureCabinClimateIntent()
                climate.settings = CabinClimateSettings(
                    targetTemperatureCelsius: 22.0,
                    enableMaxDefrost: true,
                    driverSeatHeatLevel: 3,
                    steeringWheelHeat: true
                )
                let climateResult = try Self.unwrap(try await climate.perform().value, "ConfigureCabinClimateIntent")
                try Self.expect(climateResult.succeeded, "Climate configuration failed")

                let nav = SendNavigationIntent()
                nav.destination = "Apple Park Visitor Center, Cupertino, CA"
                let navResult = try Self.unwrap(try await nav.perform().value, "SendNavigationIntent")
                try Self.expect(navResult.succeeded, "SendNavigationIntent failed")

                let state = sandbox.demoState()
                try Self.expect(state.hvacOn && state.defrostOn && state.steeringWheelHeaterOn, "Expected HVAC + defrost + wheel heat on")
                try Self.expect(state.seatHeaterLevels["Driver"] == 3, "Expected Driver seat heat 3")
                try Self.expect(state.lastNavigationDestination == "Apple Park Visitor Center, Cupertino, CA", "Destination mismatch")
                return "26°F → Defrost + Driver Seat 3 + Wheel Heat + Nav sent; flagged FR 36.5 PSI"
            }

            await recordStep(.skill, "Skill: prepare-trip (Low Battery + Hot Cabin)") {
                sandbox.applyPreset(.roadTripPrep)
                let info = try Self.unwrap(
                    try await GetVehicleInfoIntent(topics: [.battery, .range, .charging]).perform().value,
                    "GetVehicleInfoIntent"
                )
                try Self.expect(info.batteryPercent == 42, "Expected 42% battery")

                let limitIntent = SetChargeLimitIntent()
                limitIntent.percent = 90
                _ = try await limitIntent.perform()
                _ = try await StartChargingIntent().perform()

                let chargingDemo = sandbox.demoState()
                try Self.expect(chargingDemo.chargeLimitSOC == 90 && chargingDemo.chargingState == "Charging", "Expected charging to 90%")

                sandbox.applyPreset(.hotCabin)
                let coolCabin = ConfigureCabinClimateIntent()
                coolCabin.settings = CabinClimateSettings(targetTemperatureCelsius: 20.0)
                _ = try await coolCabin.perform()
                try Self.expect(abs(sandbox.demoState().targetTempF - 68.0) < 0.2 && sandbox.demoState().hvacOn, "Expected cool-down to 68°F")
                return "Raised limit to 90%, started charging at 11.5 kW, cooled 104°F cabin to 68°F"
            }

            await recordStep(.skill, "Skill: overnight-security-check") {
                var state = sandbox.applyPreset(.hotCabin)
                state.hvacOn = true
                state.chargePortDoorOpen = true
                state.chargingState = "Disconnected"
                sandbox.saveDemoState(state)

                let before = try Self.unwrap(
                    try await GetVehicleInfoIntent(topics: [.security, .charging, .battery, .climate]).perform().value,
                    "GetVehicleInfoIntent"
                )
                try Self.expect(before.isLocked == false && before.sentryModeOn == false && before.isClimateOn == true, "Expected unlocked + climate on")

                _ = try await LockVehicleIntent().perform()
                let sentry = SetSentryModeIntent()
                sentry.on = true
                _ = try await sentry.perform()
                _ = try await CloseWindowsIntent().perform()
                let closePort = SetChargePortIntent()
                closePort.action = .close
                _ = try await closePort.perform()
                _ = try await StopClimateIntent().perform()

                let after = sandbox.demoState()
                try Self.expect(after.locked && after.sentryModeOn, "Expected locked + Sentry on")
                try Self.expect(after.openClosureNames.isEmpty, "Expected all closures closed")
                try Self.expect(!after.chargePortDoorOpen && !after.hvacOn, "Expected port closed + HVAC off")
                return "Locked doors, enabled Sentry, closed vented window & charge port, stopped HVAC"
            }

            await recordStep(.skill, "Skill: software-update-advisor") {
                sandbox.applyPreset(.mildCommute)
                let status = try Self.unwrap(try await GetSoftwareStatusIntent().perform().value, "GetSoftwareStatusIntent")
                try Self.expect(status.availableVersion == "2026.38.1", "Expected pending 2026.38.1")

                let allNotes = try Self.unwrap(try await GetReleaseNotesIntent().perform().value, "GetReleaseNotesIntent")
                try Self.expect(allNotes.count == 3, "Expected 3 release notes")

                let filteredNotesIntent = GetReleaseNotesIntent()
                filteredNotesIntent.featureQuery = "FSD"
                let fsdNotes = try Self.unwrap(try await filteredNotesIntent.perform().value, "GetReleaseNotesIntent(FSD)")
                try Self.expect(fsdNotes.count == 1, "Expected 1 FSD note")

                let installIntent = InstallSoftwareUpdateIntent()
                installIntent.startTime = Date().addingTimeInterval(3600)
                _ = try await installIntent.perform()
                try Self.expect(sandbox.demoState().softwareStatus == "scheduled", "Expected scheduled software status")

                _ = try await CancelSoftwareUpdateIntent().perform()
                try Self.expect(sandbox.demoState().softwareStatus == "available", "Expected canceled back to available")
                return "Checked 2026.38.1, read 3 notes (filtered FSD), scheduled & canceled install"
            }

            await recordStep(.skill, "Skill: driving-and-energy-insights") {
                let findIntent = FindDrivesIntent()
                findIntent.filter = DriveFilterCriteria(locationQuery: "Airport", maximumResults: 5)
                let matchingDrives = try Self.unwrap(try await findIntent.perform().value, "FindDrivesIntent")
                try Self.expect(matchingDrives.count == 1, "Expected 1 Airport drive")

                let detailIntent = GetDriveDetailsIntent()
                detailIntent.drive = matchingDrives.first
                let detail = try Self.unwrap(try await detailIntent.perform().value, "GetDriveDetailsIntent")
                try Self.expect((detail.distanceMiles ?? 0) > 30, "Expected SFO drive > 30 mi")

                let recentCharges = GetRecentChargesIntent()
                recentCharges.count = 5
                let charges = try Self.unwrap(try await recentCharges.perform().value, "GetRecentChargesIntent")
                try Self.expect(charges.count == 2, "Expected 2 demo charges")

                let chargeDetail = try Self.unwrap(try await GetChargeDetailsIntent().perform().value, "GetChargeDetailsIntent")
                try Self.expect(chargeDetail.energyAddedKWH == 24.5, "Expected 24.5 kWh latest charge")

                let driveStatsIntent = GetDrivingStatsIntent()
                driveStatsIntent.period = .last7Days
                let driveStats = try Self.unwrap(try await driveStatsIntent.perform().value, "GetDrivingStatsIntent")
                try Self.expect(driveStats.driveCount == 2 && driveStats.totalDistanceMiles > 50, "Expected 2 drives > 50 mi")

                let chargeStatsIntent = GetChargingStatsIntent()
                chargeStatsIntent.period = .last7Days
                let chargeStats = try Self.unwrap(try await chargeStatsIntent.perform().value, "GetChargingStatsIntent")
                try Self.expect(chargeStats.sessionCount == 2 && chargeStats.totalEnergyAddedKWH > 70, "Expected 2 charges > 70 kWh")

                let health = try Self.unwrap(try await GetBatteryHealthIntent().perform().value, "GetBatteryHealthIntent")
                try Self.expect(health.healthPercent == 97.4, "Expected 97.4% battery health")
                return String(
                    format: "%.1f mi driven, %.1f kWh added ($%.2f), %.1f%% pack health",
                    driveStats.totalDistanceMiles,
                    chargeStats.totalEnergyAddedKWH,
                    chargeStats.totalCost ?? 0,
                    health.healthPercent ?? 0
                )
            }

            await recordStep(.skill, "Skill: vehicle-control (status and capabilities)") {
                sandbox.applyPreset(.freezingMorning)
                let before = sandbox.commandLog().count
                let cars = try Self.unwrap(try await ListCarsIntent().perform().value, "ListCarsIntent")
                let car = try Self.unwrap(cars.first, "Default demo vehicle")
                try Self.expect(car.isDefaultCar == true && car.controls?.isEmpty == false, "Expected default car and controls")
                let check = GetVehicleInfoIntent(vehicle: car, topics: [.climate])
                let info = try Self.unwrap(try await check.perform().value, "GetVehicleInfoIntent")
                try Self.expect(info.vin == car.id && info.insideTemp == 26 && info.targetTemp == 68, "Expected 26°F cabin, set to 68°F")
                try Self.expect(sandbox.commandLog().count == before, "Discovery and readings should issue no commands")
                return "\(car.name) is the default; the cabin is 26°F and the target is 68°F."
            }

            await recordStep(.skill, "Skill: vehicle-control (combined changes)") {
                sandbox.applyPreset(.freezingMorning)
                let changes = CarControlSettings()
                changes.climateOn = true
                changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
                changes.locked = true
                let control = ControlCarIntent()
                control.changes = changes
                let applied = try Self.unwrap(try await control.perform().value, "ControlCarIntent")
                let state = sandbox.demoState()
                try Self.expect(applied.succeeded && state.locked && state.hvacOn && abs(state.targetTempF - 71.6) < 0.1,
                                "Expected the default demo car locked and conditioning to 22°C")
                return applied.summary
            }

            // MARK: - 2. Climate & Comfort Siri Tools ("Warm Up" / "Cool Down" + Individual Controls)

            await recordStep(.tool, "Climate Tools: StartClimate & SetCabinTemperature") {
                sandbox.applyPreset(.freezingMorning)
                let startResult = try Self.unwrap(try await StartClimateIntent().perform().value, "StartClimateIntent")
                try Self.expect(startResult.succeeded && sandbox.demoState().hvacOn, "StartClimateIntent failed")

                sandbox.applyPreset(.hotCabin)
                let setTemp = SetCabinTemperatureIntent()
                setTemp.temperature = Measurement(value: 70, unit: .fahrenheit)
                let tempResult = try Self.unwrap(try await setTemp.perform().value, "SetCabinTemperatureIntent")
                try Self.expect(tempResult.summary.contains("Started climate"), "Expected climate auto-start summary")
                try Self.expect(sandbox.demoState().hvacOn && abs(sandbox.demoState().targetTempF - 69.8) < 0.5, "Expected HVAC on at ~70°F")
                return tempResult.summary
            }

            await recordStep(.tool, "Comfort Tools: Defrost, Seat Heat/Cool, Wheel, Dog & HEPA") {
                let defrost = SetMaxDefrostIntent()
                defrost.on = true
                _ = try await defrost.perform()
                try Self.expect(sandbox.demoState().defrostOn, "Expected Max Defrost on")

                _ = try await SetSeatClimateIntent(seat: .driver, level: 2, mode: .heat).perform()
                try Self.expect(sandbox.demoState().seatHeaterLevels["Driver"] == 2, "Expected Driver seat 2")
                _ = try await SetSeatClimateIntent(seat: .passenger, level: 1, mode: .cool).perform()
                try Self.expect(sandbox.demoState().seatHeaterLevels["Passenger"] == 1, "Expected Passenger cool 1")

                let wheel = SetSteeringWheelHeaterIntent()
                wheel.on = true
                _ = try await wheel.perform()
                try Self.expect(sandbox.demoState().steeringWheelHeaterOn, "Expected wheel heater on")

                let petOn = SetPetModeIntent()
                petOn.on = true
                _ = try await petOn.perform()
                try Self.expect(sandbox.demoState().petModeOn, "Expected Dog Mode on")

                let petOff = SetPetModeIntent()
                petOff.on = false
                _ = try await petOff.perform()
                try Self.expect(!sandbox.demoState().petModeOn, "Expected Dog Mode off")

                let hepa = SetBioweaponModeIntent()
                hepa.on = true
                _ = try await hepa.perform()
                try Self.expect(sandbox.demoState().bioweaponModeOn, "Expected Bioweapon Defense on")
                return "Verified Max Defrost, Seat Heat/Cool, Wheel Heat, Dog Mode (on/off), and HEPA"
            }

            // MARK: - 3. Doors, Closures, Charging & Convenience Siri Tools

            await recordStep(.tool, "Closure & Security Tools: Unlock, Lock, Windows, Trunk & Frunk") {
                _ = try await UnlockVehicleIntent().perform()
                try Self.expect(!sandbox.demoState().locked, "Expected unlocked")

                _ = try await LockVehicleIntent().perform()
                try Self.expect(sandbox.demoState().locked, "Expected locked")

                _ = try await VentWindowsIntent().perform()
                try Self.expect(sandbox.demoState().frontDriverWindowOpen, "Expected windows vented")

                _ = try await CloseWindowsIntent().perform()
                try Self.expect(!sandbox.demoState().frontDriverWindowOpen, "Expected windows closed")

                _ = try await OpenTrunkIntent(trunk: .rear).perform()
                try Self.expect(sandbox.demoState().rearTrunkOpen, "Expected rear trunk open")

                _ = try await OpenFrunkIntent().perform()
                try Self.expect(sandbox.demoState().frontTrunkOpen, "Expected frunk open")

                let sentryOff = SetSentryModeIntent()
                sentryOff.on = false
                _ = try await sentryOff.perform()
                try Self.expect(!sandbox.demoState().sentryModeOn, "Expected Sentry off")
                return "Verified Unlock, Lock, Vent/Close Windows, Rear Trunk, Frunk, and Sentry Off"
            }

            await recordStep(.tool, "Charging & Convenience Tools: Port, Amps, Stop Charge, Lights & Horn") {
                let openPort = SetChargePortIntent()
                openPort.action = .open
                _ = try await openPort.perform()
                try Self.expect(sandbox.demoState().chargePortDoorOpen, "Expected charge port open")

                let amps = SetChargingAmpsIntent()
                amps.amps = 32
                _ = try await amps.perform()
                try Self.expect(sandbox.demoState().chargingAmps == 32, "Expected 32A")

                _ = try await StartChargingIntent().perform()
                try Self.expect(sandbox.demoState().chargingState == "Charging", "Expected Charging")

                _ = try await StopChargingIntent().perform()
                try Self.expect(sandbox.demoState().chargingState == "Stopped", "Expected Stopped")

                let flash = try Self.unwrap(try await FlashLightsIntent().perform().value, "FlashLightsIntent")
                let honk = try Self.unwrap(try await HonkHornIntent().perform().value, "HonkHornIntent")
                try Self.expect(flash.succeeded && honk.succeeded, "Expected Flash & Honk succeeded")
                return "Verified Charge Port Open, 32A Amps, Start/Stop Charging, Flash Lights, and Honk"
            }

            // MARK: - 4. Read Tools, App Shortcuts & Spotlight Entity Queries

            await recordStep(.shortcut, "Read Tools, Shortcuts & Spotlight Entity Queries") {
                sandbox.applyPreset(.mildCommute)

                let fullStatus = try Self.unwrap(try await GetVehicleStatusIntent().perform().value, "GetVehicleStatusIntent")
                let battery = try Self.unwrap(try await GetBatteryLevelIntent().perform().value, "GetBatteryLevelIntent")
                let mileage = try Self.unwrap(try await GetVehicleMileageIntent().perform().value, "GetVehicleMileageIntent")
                let tires = try Self.unwrap(try await GetTirePressureIntent().perform().value, "GetTirePressureIntent")
                let recentDrives = try Self.unwrap(try await GetRecentDrivesIntent().perform().value, "GetRecentDrivesIntent")
                let lastDrive = try Self.unwrap(try await GetLastDriveIntent().perform().value, "GetLastDriveIntent")

                try Self.expect(fullStatus.vin == FleetDemoVehicleState.demoVIN && battery.batteryPercent == 78, "Status/battery mismatch")
                try Self.expect(
                    mileage.odometerDisplay?.contains("14") == true
                        && tires.tireSummary?.contains("42") == true
                        && recentDrives.count == 2,
                    "Mileage/tires/drives mismatch"
                )
                try Self.expect(lastDrive.distanceMiles == 14.6, "Last drive distance mismatch")

                _ = await FleetSpotlightIndexer.reindexAll()

                let suggestedVehicles = try await VehicleEntityQuery().suggestedEntities()
                let matchedMyCar = try await VehicleEntityQuery().entities(matching: "my car")
                let matchedCarStatus = try await VehicleStatusEntityQuery().entities(matching: "my car")
                let suggestedDrives = try await DriveEntityQuery().suggestedEntities()
                let suggestedUpdates = try await SoftwareUpdateEntityQuery().suggestedEntities()
                let suggestedNotes = try await ReleaseNoteEntityQuery().suggestedEntities()
                let suggestedCharges = try await ChargeSessionEntityQuery().suggestedEntities()

                let warmUpSummary = try await CarSiriVoicePhrase.warmUp.perform().summary

                try Self.expect(
                    !suggestedVehicles.isEmpty
                        && matchedMyCar.first?.id == FleetDemoVehicleState.demoVIN
                        && matchedCarStatus.first?.vin == FleetDemoVehicleState.demoVIN
                        && warmUpSummary.contains("Climate is starting")
                        && !suggestedDrives.isEmpty
                        && !suggestedUpdates.isEmpty
                        && !suggestedNotes.isEmpty
                        && !suggestedCharges.isEmpty,
                    "Expected 'my car' EntityStringQuery + voice phrase + all 6 EntityQueries to resolve"
                )
                return "Verified 'my car' entity lookup, voice phrase, Spotlight & all 6 EntityQueries"
            }

            await recordStep(.shortcut, "Siri Dynamic Widgets: Apple Maps Drive Routes & Live Snippets") {
                let drives = try Self.unwrap(try await GetRecentDrivesIntent().perform().value, "GetRecentDrivesIntent")
                try Self.expect(drives.count == 2, "Expected 2 demo drives for route widget")
                let firstDrive = drives[0]
                try Self.expect(firstDrive.appleMapsRouteURL != nil, "Expected Apple Maps route URL on DriveEntity")

                let points = await SiriMapSnapshotRenderer.resolveRoutePoints(
                    for: firstDrive,
                    service: .make(),
                    allowGeocoding: false
                )
                try Self.expect(points.count >= 6 && points.contains(where: \.isAutopilotActive), "Expected GPS polyline with Autopilot segments")

                let routeSnippet = DriveRouteSnippetIntent(drives: drives, vehicleName: "Midnight", sessionKey: "verify-route")
                _ = try await routeSnippet.perform()

                _ = try await SelectSnippetItemIntent(sessionKey: "verify-route", targetIndex: 1).perform()
                try Self.expect(
                    SiriSnippetStateStore.shared.selectedDriveIndex(for: "verify-route", count: drives.count) == 1,
                    "Expected drive stepper to advance to index 1"
                )

                let beforeStyle = SiriSnippetStateStore.shared.mapStyle(for: "drive")
                _ = try await ToggleSnippetMapStyleIntent(scope: "drive").perform()
                let afterStyle = SiriSnippetStateStore.shared.mapStyle(for: "drive")
                try Self.expect(afterStyle == beforeStyle.toggled, "Expected map style to toggle")
                _ = try await ToggleSnippetMapStyleIntent(scope: "drive").perform()

                let charges = try Self.unwrap(try await GetRecentChargesIntent().perform().value, "GetRecentChargesIntent")
                try Self.expect(charges.first?.appleMapsLocationURL != nil, "Expected Apple Maps charger URL")
                _ = try await ChargeSessionSnippetIntent(sessions: charges, vehicleName: "Midnight", sessionKey: "verify-charge").perform()

                let vehicleEntity = VehicleEntity(id: FleetDemoVehicleState.demoVIN, name: "Midnight")
                _ = try await ClimateControlSnippetIntent(vehicle: vehicleEntity, appliedSummary: "Warming cabin").perform()
                _ = try await AdjustSnippetClimateIntent(vehicle: vehicleEntity, targetFahrenheit: 72, turnOff: false).perform()
                try Self.expect(sandbox.demoState().hvacOn && abs(sandbox.demoState().targetTempF - 71.6) < 0.5, "Expected snippet climate +/- control to set ~72°F")

                return "Verified \(points.count)-pt GPS route + Autopilot segments, Apple Maps URLs, Satellite toggle, drive stepper & live climate widget"
            }
        }

        totalConfirmationsRecorded = confirmationBox.count
        lastCompletedAt = .now
        isRunning = false

        Self.writeReportFile(
            results: results,
            confirmationsRecorded: totalConfirmationsRecorded,
            commandLog: sandbox.commandLog()
        )

        print(
            "[SiriVerify] === COMPLETED: \(passedCount)/\(results.count) PASSED, \(failedCount) FAILED, \(totalConfirmationsRecorded) SAFETY CONFIRMATIONS RECORDED, \(sandbox.commandLog().count) LOGGED COMMANDS ==="
        )
    }

    private struct VerificationReportPayload: Codable {
        struct StepPayload: Codable {
            let category: String
            let title: String
            let passed: Bool
            let detail: String
            let durationMS: Int
        }

        let completedAt: String
        let passedCount: Int
        let failedCount: Int
        let confirmationsRecorded: Int
        let interceptedCommandCount: Int
        let steps: [StepPayload]
        let sampleInterceptedCommands: [String]
    }

    private static func writeReportFile(
        results: [SiriVerificationStepResult],
        confirmationsRecorded: Int,
        commandLog: [FleetSimulatedCommandEntry]
    ) {
        let payload = VerificationReportPayload(
            completedAt: ISO8601DateFormatter().string(from: .now),
            passedCount: results.filter(\.passed).count,
            failedCount: results.filter { !$0.passed }.count,
            confirmationsRecorded: confirmationsRecorded,
            interceptedCommandCount: commandLog.count,
            steps: results.map {
                .init(
                    category: $0.category.rawValue,
                    title: $0.title,
                    passed: $0.passed,
                    detail: $0.detail,
                    durationMS: $0.durationMS
                )
            },
            sampleInterceptedCommands: commandLog.prefix(25).map { entry in
                if let params = entry.parametersSummary, !params.isEmpty {
                    return "\(entry.action)(\(params))"
                }
                return entry.action
            }
        )
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let target = docs.appendingPathComponent("siri-verification-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: target, options: .atomic)
        }
    }

    private func recordStep(
        _ category: SiriVerificationStepResult.Category,
        _ title: String,
        work: () async throws -> String
    ) async {
        let start = ContinuousClock.now
        do {
            let detail = try await work()
            let elapsed = start.duration(to: .now)
            let ms = Int((Double(elapsed.components.seconds) * 1_000) + (Double(elapsed.components.attoseconds) / 1e15))
            let item = SiriVerificationStepResult(
                category: category,
                title: title,
                passed: true,
                detail: detail,
                durationMS: max(ms, 1)
            )
            results.append(item)
            print("[SiriVerify] PASS [\(category.rawValue)] \(title) (\(item.durationMS) ms) — \(detail)")
        } catch {
            let elapsed = start.duration(to: .now)
            let ms = Int((Double(elapsed.components.seconds) * 1_000) + (Double(elapsed.components.attoseconds) / 1e15))
            let item = SiriVerificationStepResult(
                category: category,
                title: title,
                passed: false,
                detail: error.localizedDescription,
                durationMS: max(ms, 1)
            )
            results.append(item)
            print("[SiriVerify] FAIL [\(category.rawValue)] \(title) (\(item.durationMS) ms) — \(error.localizedDescription)")
        }
    }

    private struct VerificationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw VerificationFailure(message: message)
        }
    }

    private static func unwrap<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw VerificationFailure(message: "\(label) returned nil")
        }
        return value
    }
}

private nonisolated final class ConfirmationPromptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var prompts: [String] = []

    init() {}

    func record(_ prompt: String) {
        lock.lock()
        prompts.append(prompt)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return prompts.count
    }
}
