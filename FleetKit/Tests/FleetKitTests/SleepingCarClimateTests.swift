import AppIntents
import Foundation
import Synchronization
import Testing
@testable import FleetKit

struct SleepingCarClimateTests {
    private static let vin = "VIN-1"
    private static let vehicle = VehicleEntity(id: vin, name: "Roadrunner")

    private static func statusPayload(_ status: String) -> Data {
        Data(#"{"status":"\#(status)"}"#.utf8)
    }

    private static func tessieVehiclesJSON(hvacOn: Bool, timestampMS: Int64) -> Data {
        let json = """
        {
          "results": [
            {
              "vin":"VIN-1",
              "is_active":true,
              "last_state":{
                "display_name":"Roadrunner",
                "climate_state":{
                  "inside_temp":20.0,
                  "outside_temp":10.0,
                  "is_climate_on":\(hvacOn),
                  "timestamp":\(timestampMS)
                },
                "gui_settings":{"gui_temperature_units":"F"}
              }
            }
          ]
        }
        """
        return Data(json.utf8)
    }

    private static func hasAsyncWakeQuery(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains(where: { $0.name == "wait_for_completion" && $0.value == "false" }) == true
    }

    // MARK: - Tessie sleeping fast path

    @Test(arguments: ["asleep", "waiting_for_sleep"])
    func tessieSleepingSingleClimateIntentsUseAsyncFastPath(sleepStatus: String) async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/status":
                return (200, Self.statusPayload(sleepStatus))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, service, requests in
            // 1. StartClimateIntent
            let start = StartClimateIntent()
            start.vehicle = Self.vehicle
            let startResult = try #require(try await start.perform().value)
            #expect(startResult.succeeded)
            #expect(startResult.deliveryState == .wakingVehicle)
            #expect(startResult.summary.localizedCaseInsensitiveContains("asleep"))
            #expect(startResult.summary.localizedCaseInsensitiveContains("wake"))

            let startPosts = requests().filter { $0.httpMethod == "POST" }
            let startPost = try #require(startPosts.last)
            #expect(startPost.url?.path == "/VIN-1/command/start_climate")
            #expect(Self.hasAsyncWakeQuery(startPost))
            #expect(startPost.timeoutInterval == FleetKitConfig.requestTimeout)
            #expect(requests().contains { $0.url?.path == "/VIN-1/status" })

            // Waking receipt must NOT claim HVAC is recently started.
            let wakingReceipt = try #require(
                ClimateCommandReceipt.latest(
                    vin: Self.vin,
                    scope: service.sessionScopeID,
                    group: service.appGroupIdentifier
                )
            )
            #expect(wakingReceipt.deliveryState == .wakingVehicle)
            #expect(wakingReceipt.isWaking)
            #expect(!wakingReceipt.recentlyStarted())

            // Follow-up snippet adjustment must still send start_climate synchronously.
            let adjust = AdjustSnippetClimateIntent(
                vehicle: Self.vehicle,
                targetFahrenheit: 72,
                turnOff: false,
                interactionID: wakingReceipt.interactionID,
                scope: service.sessionScopeID
            )
            _ = try await adjust.perform()
            let afterAdjustPosts = requests().filter { $0.httpMethod == "POST" }
            let adjustPaths = afterAdjustPosts.suffix(2).compactMap { $0.url?.lastPathComponent }
            #expect(adjustPaths == ["start_climate", "set_temperatures"])
            #expect(!Self.hasAsyncWakeQuery(afterAdjustPosts[afterAdjustPosts.count - 2]))
            #expect(afterAdjustPosts[afterAdjustPosts.count - 2].timeoutInterval == FleetKitConfig.commandTimeout)

            // 2. StopClimateIntent
            let stop = StopClimateIntent()
            stop.vehicle = Self.vehicle
            let stopResult = try #require(try await stop.perform().value)
            #expect(stopResult.deliveryState == .wakingVehicle)
            let stopPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(stopPost.url?.path == "/VIN-1/command/stop_climate")
            #expect(Self.hasAsyncWakeQuery(stopPost))

            // 3. SetMaxDefrostIntent
            let defrost = SetMaxDefrostIntent()
            defrost.vehicle = Self.vehicle
            defrost.on = true
            let defrostResult = try #require(try await defrost.perform().value)
            #expect(defrostResult.deliveryState == .wakingVehicle)
            let defrostPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(defrostPost.url?.path == "/VIN-1/command/start_max_defrost")
            #expect(Self.hasAsyncWakeQuery(defrostPost))

            // 4. SetPetModeIntent
            let pet = SetPetModeIntent()
            pet.vehicle = Self.vehicle
            pet.on = true
            let petResult = try #require(try await pet.perform().value)
            #expect(petResult.deliveryState == .wakingVehicle)
            let petPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(petPost.url?.path == "/VIN-1/command/set_climate_keeper_mode")
            #expect(Self.hasAsyncWakeQuery(petPost))

            // 5. SetBioweaponModeIntent
            let bio = SetBioweaponModeIntent()
            bio.vehicle = Self.vehicle
            bio.on = true
            let bioResult = try #require(try await bio.perform().value)
            #expect(bioResult.deliveryState == .wakingVehicle)
            let bioPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(bioPost.url?.path == "/VIN-1/command/set_bioweapon_mode")
            #expect(Self.hasAsyncWakeQuery(bioPost))

            // 6. Single-step ConfigureCabinClimateIntent (enableMaxDefrost only)
            let configure = ConfigureCabinClimateIntent()
            configure.vehicle = Self.vehicle
            configure.settings = CabinClimateSettings(enableMaxDefrost: true)
            let configureResult = try #require(try await configure.perform().value)
            #expect(configureResult.deliveryState == .wakingVehicle)
            let configurePost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(configurePost.url?.path == "/VIN-1/command/start_max_defrost")
            #expect(Self.hasAsyncWakeQuery(configurePost))

            // 7. Single-step ControlCarIntent (climateOn only)
            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.climateOn = true
            control.changes = changes
            let controlResult = try #require(try await control.perform().value)
            #expect(controlResult.deliveryState == .wakingVehicle)
            let controlPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(controlPost.url?.path == "/VIN-1/command/start_climate")
            #expect(Self.hasAsyncWakeQuery(controlPost))
        }
    }

    @MainActor
    @Test func climateSnippetViewDisplaysWakingStateUntilNewerObservationArrives() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let wakingReceipt = ClimateCommandReceipt(
            sessionScope: "test",
            interactionID: "card-1",
            date: now,
            running: true,
            startedAt: now,
            summary: "Waking Roadrunner and starting climate",
            deliveryState: .wakingVehicle
        )
        #expect(wakingReceipt.isWaking)
        #expect(!wakingReceipt.recentlyStarted(at: now.addingTimeInterval(1)))

        let viewWithoutStatus = ClimateControlSnippetView(
            vehicle: Self.vehicle,
            status: nil,
            appliedSummary: wakingReceipt.summary,
            receipt: wakingReceipt,
            interactionID: "card-1",
            sessionScope: "test"
        )
        #expect(viewWithoutStatus.isWaking)

        let olderSnapshot = FleetSnapshotInfo(
            vin: Self.vin,
            hvacOn: false,
            updatedAt: Int64(now.addingTimeInterval(-5).timeIntervalSince1970 * 1_000)
        )
        let viewWithOlderStatus = ClimateControlSnippetView(
            vehicle: Self.vehicle,
            status: VehicleStatusEntity(snapshot: olderSnapshot, vehicleName: Self.vehicle.name),
            appliedSummary: wakingReceipt.summary,
            receipt: wakingReceipt,
            interactionID: "card-1",
            sessionScope: "test"
        )
        #expect(viewWithOlderStatus.isWaking)

        let newerSnapshot = FleetSnapshotInfo(
            vin: Self.vin,
            hvacOn: true,
            updatedAt: Int64(now.addingTimeInterval(5).timeIntervalSince1970 * 1_000)
        )
        let viewWithNewerStatus = ClimateControlSnippetView(
            vehicle: Self.vehicle,
            status: VehicleStatusEntity(snapshot: newerSnapshot, vehicleName: Self.vehicle.name),
            appliedSummary: wakingReceipt.summary,
            receipt: wakingReceipt,
            interactionID: "card-1",
            sessionScope: "test"
        )
        #expect(!viewWithNewerStatus.isWaking)
        #expect(viewWithNewerStatus.displayedRunning == true)
    }

    // MARK: - Awake / status fallback / 401 propagation

    @Test(arguments: [
        (200, #"{"status":"awake"}"#),
        (500, #"{"error":"temporary status error"}"#),
        (200, #"{"unexpected":true}"#)
    ])
    func tessieAwakeAndStatusFallbackStaySynchronousWithCommandTimeout(
        statusCode: Int,
        statusBody: String
    ) async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/status":
                return (statusCode, Data(statusBody.utf8))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, service, requests in
            let start = StartClimateIntent()
            start.vehicle = Self.vehicle
            let result = try #require(try await start.perform().value)
            #expect(result.succeeded)
            #expect(result.deliveryState == .confirmed)

            let post = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(post.url?.path == "/VIN-1/command/start_climate")
            #expect(!Self.hasAsyncWakeQuery(post))
            #expect(post.timeoutInterval == FleetKitConfig.commandTimeout)

            let receipt = try #require(
                ClimateCommandReceipt.latest(
                    vin: Self.vin,
                    scope: service.sessionScopeID,
                    group: service.appGroupIdentifier
                )
            )
            #expect(!receipt.isWaking)
            #expect(receipt.recentlyStarted())
        }
    }

    @Test func tessieStatus401SurfacesSessionExpiredWithoutSendingCommand() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/status":
                return (401, Data(#"{"error":"Unauthorized"}"#.utf8))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let start = StartClimateIntent()
            start.vehicle = Self.vehicle
            do {
                _ = try await start.perform()
                Issue.record("Expected FleetKitError.sessionExpired")
            } catch FleetKitError.sessionExpired {
                // Expected.
            } catch {
                Issue.record("Expected FleetKitError.sessionExpired, got \(error)")
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.isEmpty)
        }
    }

    @Test func setCabinTemperatureIntentStaysSynchronousEvenWhenVehicleIsAsleep() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/status":
                return (200, Self.statusPayload("asleep"))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let intent = SetCabinTemperatureIntent()
            intent.vehicle = Self.vehicle
            intent.temperature = Measurement(value: 72, unit: .fahrenheit)
            let result = try #require(try await intent.perform().value)
            #expect(result.succeeded)
            #expect(result.deliveryState == .confirmed)

            #expect(!requests().contains { $0.url?.path == "/VIN-1/status" })
            let posts = requests().filter { $0.httpMethod == "POST" }
            #expect(posts.compactMap { $0.url?.lastPathComponent } == ["start_climate", "set_temperatures"])
            for post in posts {
                #expect(!Self.hasAsyncWakeQuery(post))
                #expect(post.timeoutInterval == FleetKitConfig.commandTimeout)
            }
        }
    }

    // MARK: - Teslascope provider behavior

    @Test func teslascopeClimateCommandsSkipStatusAndUseCommandTimeout() async throws {
        let testID = UUID().uuidString
        let vin = "5YJ3E1EA7KF000001"
        SiriToolMockURLProtocol.register(id: testID) { request in
            switch request.url?.path {
            case "/api/account/tesla-accounts":
                return (200, Data(#"{"code":200,"response":[{"id":1}]}"#.utf8))
            case "/api/account/tesla-account/1/vehicles":
                let json = #"{"code":200,"response":[{"public_id":"example-car","vin":"\#(vin)","name":"Roadrunner"}]}"#
                return (200, Data(json.utf8))
            case "/api/vehicle/example-car/command/startAC":
                return (200, Data(#"{"code":200,"response":"Command accepted by vehicle."}"#.utf8))
            default:
                Issue.record("Unexpected Teslascope request: \(request.url?.path ?? "")")
                return (404, Data())
            }
        }
        defer { SiriToolMockURLProtocol.unregister(id: testID) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SiriToolMockURLProtocol.self]
        config.httpAdditionalHeaders = [SiriToolMockURLProtocol.headerName: testID]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let suiteName = "SleepingCarClimateTests.\(testID)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenStore = FleetSharedTokenStore(appGroup: suiteName) { provider in
            provider == .teslascope ? "teslascope-token" : nil
        }
        tokenStore.selectProvider(.teslascope)
        defaults.set(vin, forKey: FleetKitConfig.selectedVINDefaultsKey)

        let sandbox = FleetSandboxStore(appGroup: suiteName)
        sandbox.setMode(.live)
        let client = FleetIntentClient(session: session, tokenStore: tokenStore)
        let service = FleetIntentService(client: client, sandbox: sandbox)

        try await FleetIntentService.$testingOverride.withValue(service) {
            let start = StartClimateIntent()
            start.vehicle = VehicleEntity(id: vin, name: "Roadrunner")
            let result = try #require(try await start.perform().value)
            #expect(result.succeeded)
            #expect(result.deliveryState == .confirmed)

            let allRequests = SiriToolMockURLProtocol.requests(for: testID)
            #expect(!allRequests.contains { $0.url?.path.contains("/status") == true })
            let post = try #require(allRequests.last(where: { $0.httpMethod == "POST" }))
            #expect(post.url?.path == "/api/vehicle/example-car/command/startAC")
            #expect(post.url?.query == nil)
            #expect(post.timeoutInterval == FleetKitConfig.commandTimeout)
        }
    }

    // MARK: - Skip redundant auto_conditioning_start

    @Test func climateIntentsSkipRedundantStartWhenHVACConfirmedRunningAndResetOnStopOrWake() async throws {
        let nowMS = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Self.tessieVehiclesJSON(hvacOn: true, timestampMS: nowMS))
            case "/VIN-1/status":
                return (200, Self.statusPayload("awake"))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, service, requests in
            // Warm the roster cache so climate_state.is_climate_on == true is known.
            _ = try await service.vehicles()
            let runningBeforeStop = await service.isClimateLikelyRunning(vin: Self.vin)
            #expect(runningBeforeStop)

            // 1. SetCabinTemperatureIntent skips start_climate.
            let setTemp = SetCabinTemperatureIntent()
            setTemp.vehicle = Self.vehicle
            setTemp.temperature = Measurement(value: 71, unit: .fahrenheit)
            _ = try await setTemp.perform()

            // 2. ConfigureCabinClimateIntent skips start_climate.
            let configure = ConfigureCabinClimateIntent()
            configure.vehicle = Self.vehicle
            configure.settings = CabinClimateSettings(
                targetTemperatureCelsius: 21.5,
                enableMaxDefrost: true,
                steeringWheelHeat: true
            )
            _ = try await configure.perform()

            // 3. SetSeatClimateIntent skips start_climate.
            let seat = SetSeatClimateIntent()
            seat.vehicle = Self.vehicle
            seat.seat = .driver
            seat.mode = .heat
            seat.level = 2
            _ = try await seat.perform()

            // 4. SetSteeringWheelHeaterIntent skips start_climate.
            let wheel = SetSteeringWheelHeaterIntent()
            wheel.vehicle = Self.vehicle
            wheel.on = true
            _ = try await wheel.perform()

            // 5. ControlCarIntent skips start_climate.
            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22, enableMaxDefrost: false)
            control.changes = changes
            _ = try await control.perform()

            let postsBeforeStop = requests().filter { $0.httpMethod == "POST" }
            #expect(!postsBeforeStop.contains { $0.url?.lastPathComponent == "start_climate" })

            // Stopping climate records a running=false receipt newer than the roster snapshot.
            let stop = StopClimateIntent()
            stop.vehicle = Self.vehicle
            _ = try await stop.perform()
            let runningAfterStop = await service.isClimateLikelyRunning(vin: Self.vin)
            #expect(!runningAfterStop)

            // Next SetCabinTemperatureIntent must send start_climate again.
            let afterStopCount = requests().count
            let setTempAgain = SetCabinTemperatureIntent()
            setTempAgain.vehicle = Self.vehicle
            setTempAgain.temperature = Measurement(value: 73, unit: .fahrenheit)
            _ = try await setTempAgain.perform()
            let afterStopPosts = requests().dropFirst(afterStopCount).filter { $0.httpMethod == "POST" }
            #expect(afterStopPosts.compactMap { $0.url?.lastPathComponent } == ["start_climate", "set_temperatures"])
        }
    }

    // MARK: - Sequential cabin commands & partial failures

    @Test func frontSeatsAndConfigureCabinSendCommandsInRequestedOrder() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, _, requests in
            let configure = ConfigureCabinClimateIntent()
            configure.vehicle = Self.vehicle
            configure.settings = CabinClimateSettings(
                targetTemperatureCelsius: 21,
                enableMaxDefrost: true,
                driverSeatHeatLevel: 3,
                steeringWheelHeat: true
            )
            let result = try #require(try await configure.perform().value)
            #expect(result.succeeded)
            #expect(result.deliveryState == .confirmed)

            let posts = requests().filter { $0.httpMethod == "POST" }
            let paths = posts.compactMap { $0.url?.lastPathComponent }
            #expect(paths == ["start_climate", "set_temperatures", "start_max_defrost", "set_seat_heat", "start_steering_wheel_heater"])

            // Front seats issues both front_left and front_right.
            let beforeSeats = requests().count
            let seats = SetSeatClimateIntent()
            seats.vehicle = Self.vehicle
            seats.seat = .frontSeats
            seats.mode = .heat
            seats.level = 2
            let seatResult = try #require(try await seats.perform().value)
            #expect(seatResult.succeeded)
            let seatPosts = requests().dropFirst(beforeSeats).filter { $0.httpMethod == "POST" }
            #expect(seatPosts.compactMap { $0.url?.lastPathComponent } == ["set_seat_heat", "set_seat_heat"])
        }
    }

    @Test func controlCarSendsStepsInOrderAndStopsAtFirstFailure() async throws {
        // Happy path: cabin settings followed by lock go out one at a time, in order.
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, _, requests in
            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(
                targetTemperatureCelsius: 22,
                enableMaxDefrost: true,
                steeringWheelHeat: true
            )
            changes.locked = true
            control.changes = changes

            let result = try #require(try await control.perform().value)
            #expect(result.succeeded)
            #expect(result.deliveryState == .confirmed)
            #expect(result.appliedValue == "climate on, 22.0°C, max defrost on, steering wheel heat on, lock doors")

            let posts = requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent }
            #expect(posts == ["start_climate", "set_temperatures", "start_max_defrost", "start_steering_wheel_heater", "lock"])
        }

        // Failure path: the sequence stops at the failed step, reports what was applied,
        // and lists every later step that was never sent.
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/command/start_max_defrost":
                return (500, Data(#"{"error":"defrost failed"}"#.utf8))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(
                targetTemperatureCelsius: 22,
                enableMaxDefrost: true,
                steeringWheelHeat: true
            )
            changes.locked = true
            control.changes = changes

            let partial = try #require(try await control.perform().value)
            #expect(!partial.succeeded)
            #expect(partial.appliedValue == "climate on, 22.0°C")
            #expect(partial.summary.contains("I couldn't confirm max defrost on: defrost failed."))
            #expect(partial.summary.contains("Not sent: steering wheel heat on, lock doors."))

            let posts = requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent }
            #expect(posts == ["start_climate", "set_temperatures", "start_max_defrost"])
        }
    }

    // MARK: - Progress heartbeat, awake-roster optimization, TTL, receipts, and edge cases

    @Test func intentProgressHeartbeatTicksAndCompletesAndStopsOnError() async throws {
        let successProgress = Progress()
        let result = try await IntentProgressHeartbeat.run(
            progress: successProgress,
            description: "Starting climate in Roadrunner",
            interval: .milliseconds(15)
        ) {
            try await Task.sleep(for: .milliseconds(70))
            return "done"
        }
        #expect(result == "done")
        #expect(successProgress.totalUnitCount >= IntentProgressHeartbeat.initialTotalUnitCount)
        #expect(successProgress.completedUnitCount == successProgress.totalUnitCount)
        #expect(successProgress.localizedDescription == "Starting climate in Roadrunner")
        #expect(successProgress.localizedAdditionalDescription?.isEmpty == false)

        let errorProgress = Progress()
        await #expect(throws: FleetKitError.self) {
            _ = try await IntentProgressHeartbeat.run(
                progress: errorProgress,
                description: "Updating Roadrunner",
                interval: .milliseconds(15)
            ) { () async throws -> String in
                try await Task.sleep(for: .milliseconds(40))
                throw FleetKitError.api("command failed")
            }
        }
        let capturedAfterError = errorProgress.completedUnitCount
        #expect(capturedAfterError > IntentProgressHeartbeat.initialTotalUnitCount / 20)
        #expect(capturedAfterError < errorProgress.totalUnitCount)
        try await Task.sleep(for: .milliseconds(45))
        // Heartbeat must have fully exited before returning so Progress is never mutated post-perform.
        #expect(errorProgress.completedUnitCount == capturedAfterError)
    }

    @Test func freshOnlineRosterSkipsStatusProbeWhileStaleOnlineStillProbes() async throws {
        let nowMS = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let staleMS = Int64(Date.now.addingTimeInterval(-300).timeIntervalSince1970 * 1_000)

        func rosterJSON(timestampMS: Int64) -> Data {
            Data("""
            {
              "results": [
                {
                  "vin":"VIN-1",
                  "is_active":true,
                  "last_state":{
                    "state":"online",
                    "display_name":"Roadrunner",
                    "vehicle_state":{"timestamp":\(timestampMS)}
                  }
                }
              ]
            }
            """.utf8)
        }

        // Fresh online roster (<30s) skips GET /VIN-1/status and runs synchronously.
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, rosterJSON(timestampMS: nowMS))
            case "/VIN-1/status":
                Issue.record("Expected /status probe to be skipped for fresh online roster")
                return (200, Self.statusPayload("asleep"))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let start = StartClimateIntent()
            start.vehicle = Self.vehicle
            let result = try #require(try await start.perform().value)
            #expect(result.deliveryState == .confirmed)
            #expect(!requests().contains { $0.url?.path == "/VIN-1/status" })
            let post = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(!Self.hasAsyncWakeQuery(post))
        }

        // Stale online roster (5m old) MUST still probe GET /VIN-1/status and take fast path if asleep.
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, rosterJSON(timestampMS: staleMS))
            case "/VIN-1/status":
                return (200, Self.statusPayload("asleep"))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let start = StartClimateIntent()
            start.vehicle = Self.vehicle
            let result = try #require(try await start.perform().value)
            #expect(result.deliveryState == .wakingVehicle)
            #expect(requests().contains { $0.url?.path == "/VIN-1/status" })
            let post = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(Self.hasAsyncWakeQuery(post))
        }
    }

    @Test func controlCarHonorsExplicitClimateOnWhileSkippingImplicitStart() async throws {
        let nowMS = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Self.tessieVehiclesJSON(hvacOn: true, timestampMS: nowMS))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, service, requests in
            _ = try await service.vehicles()
            #expect(await service.isClimateLikelyRunning(vin: Self.vin))

            // Explicit climateOn == true must NOT be dropped even when HVAC is likely running.
            let explicit = ControlCarIntent()
            explicit.vehicle = Self.vehicle
            let explicitChanges = CarControlSettings()
            explicitChanges.climateOn = true
            explicitChanges.locked = true
            explicit.changes = explicitChanges
            let explicitResult = try #require(try await explicit.perform().value)
            #expect(explicitResult.succeeded)
            #expect(explicitResult.appliedValue == "climate on, lock doors")
            let explicitPosts = requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent }
            #expect(explicitPosts == ["start_climate", "lock"])

            // Implicit HVAC prerequisite (target temperature without climateOn == true) DOES skip start_climate.
            let beforeImplicit = requests().count
            let implicit = ControlCarIntent()
            implicit.vehicle = Self.vehicle
            let implicitChanges = CarControlSettings()
            implicitChanges.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
            implicitChanges.locked = true
            implicit.changes = implicitChanges
            let implicitResult = try #require(try await implicit.perform().value)
            #expect(implicitResult.succeeded)
            #expect(implicitResult.appliedValue == "22.0°C, lock doors")
            let implicitPosts = requests().dropFirst(beforeImplicit).filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent }
            #expect(implicitPosts == ["set_temperatures", "lock"])
        }
    }

    @Test func intentProgressHeartbeatKeepsChangingForSlowMultiCommandSequences() {
        // A sleeping car can need a status probe plus several 95s commands, so progress must keep
        // changing well past the ~90s where the old heartbeat stopped at 95%.
        var completed = IntentProgressHeartbeat.initialTotalUnitCount / 20
        var total = IntentProgressHeartbeat.initialTotalUnitCount
        var previousFraction = Double(completed) / Double(total)
        for _ in 0..<200 { // 200 ticks × 5s ≈ 17 minutes
            let next = IntentProgressHeartbeat.nextTick(completed: completed, total: total)
            #expect(next.completed > completed)
            #expect(next.completed < next.total)
            let fraction = Double(next.completed) / Double(next.total)
            #expect(fraction >= previousFraction)
            (completed, total, previousFraction) = (next.completed, next.total, fraction)
        }
    }

    @Test func configureCabinAndFrontSeatsReportPartialFailuresInsteadOfThrowing() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/command/start_max_defrost":
                return (500, Data(#"{"error":"defrost error"}"#.utf8))
            default:
                if request.url?.path == "/VIN-1/command/set_seat_heat",
                   request.url?.query?.contains("front_right") == true {
                    return (500, Data(#"{"error":"seat error"}"#.utf8))
                }
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, _, requests in
            let configure = ConfigureCabinClimateIntent()
            configure.vehicle = Self.vehicle
            configure.settings = CabinClimateSettings(
                targetTemperatureCelsius: 21,
                enableMaxDefrost: true,
                driverSeatHeatLevel: 3
            )
            let configured = try #require(try await configure.perform().value)
            #expect(!configured.succeeded)
            #expect(configured.appliedValue == "climate on, 21.0°C")
            #expect(configured.summary.contains("I couldn't confirm max defrost on: defrost error."))
            #expect(configured.summary.contains("Not sent: driver seat heat 3."))
            #expect(!requests().contains { $0.url?.lastPathComponent == "set_seat_heat" })

            let seats = SetSeatClimateIntent()
            seats.vehicle = Self.vehicle
            seats.seat = .frontSeats
            seats.mode = .heat
            seats.level = 2
            let seatResult = try #require(try await seats.perform().value)
            #expect(!seatResult.succeeded)
            #expect(seatResult.summary.contains("driver seat heat 2"))
            #expect(seatResult.summary.contains("I couldn't confirm passenger seat heat 2: seat error."))
        }
    }

    @Test func onlyLongRunningIntentsWaitOutAFullProviderWake() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, _, requests in
            // Lock only gets the standard ~30s background window, so its request must fail
            // within that window instead of being killed by the system.
            let lock = LockVehicleIntent()
            lock.vehicle = Self.vehicle
            _ = try await lock.perform()
            let lockPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(lockPost.url?.lastPathComponent == "lock")
            #expect(lockPost.timeoutInterval == FleetKitConfig.requestTimeout)

            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.locked = true
            control.changes = changes
            _ = try await control.perform()
            let controlPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(controlPost.timeoutInterval == FleetKitConfig.commandTimeout)
        }
    }

    @Test func widgetShowsClimateStartingUntilTheCarReportsHVACOn() {
        var snapshot = FleetWidgetSnapshot.sample
        snapshot.climateOn = false
        #expect(snapshot.climateDescription == "Climate off")

        let tappedAt = Date.now.addingTimeInterval(-10)
        snapshot.climateStartRequestedAt = tappedAt
        #expect(snapshot.isClimateStarting())
        #expect(snapshot.climateDescription == "Climate starting…")
        #expect(!snapshot.isClimateStarting(at: tappedAt.addingTimeInterval(FleetWidgetSnapshot.climateStartWindow + 1)))

        snapshot.climateOn = true
        #expect(!snapshot.isClimateStarting())
        #expect(snapshot.climateDescription == "Climate on")
    }

    @Test func multiStepIntentsNeverSendConcurrentCommands() async throws {
        let inFlight = Mutex<Int>(0)
        let maxConcurrency = Mutex<Int>(0)

        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            if request.httpMethod == "POST" {
                let current = inFlight.withLock { value -> Int in
                    value += 1
                    return value
                }
                maxConcurrency.withLock { peak in
                    if current > peak { peak = current }
                }
                Thread.sleep(forTimeInterval: 0.025)
                inFlight.withLock { $0 -= 1 }
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, _, _ in
            // 1. Turning off both front seats when car is not confirmed awake runs sequentially.
            let seatsOff = SetSeatClimateIntent()
            seatsOff.vehicle = Self.vehicle
            seatsOff.seat = .frontSeats
            seatsOff.mode = .heat
            seatsOff.level = 0
            _ = try await seatsOff.perform()
            #expect(maxConcurrency.withLock { $0 } == 1)

            // 2. ConfigureCabinClimateIntent with only defrost + bioweapon (no start_climate).
            maxConcurrency.withLock { $0 = 0 }
            let configure = ConfigureCabinClimateIntent()
            configure.vehicle = Self.vehicle
            configure.settings = CabinClimateSettings(
                enableMaxDefrost: true,
                enableBioweaponDefenseMode: true
            )
            _ = try await configure.perform()
            #expect(maxConcurrency.withLock { $0 } == 1)

            // 3. ControlCarIntent with HVAC, several cabin settings, Dog Mode, and lock.
            maxConcurrency.withLock { $0 = 0 }
            let control = ControlCarIntent()
            control.vehicle = Self.vehicle
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(
                targetTemperatureCelsius: 21,
                enableMaxDefrost: true,
                driverSeatHeatLevel: 2,
                steeringWheelHeat: true,
                enablePetMode: true
            )
            changes.locked = true
            control.changes = changes
            _ = try await control.perform()
            #expect(maxConcurrency.withLock { $0 } == 1)
        }
    }

    @Test func skippedClimateStartPreservesOriginalStartedAtTTL() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, service, _ in
            let scope = try #require(service.sessionScopeID)
            let originalStart = Date.now.addingTimeInterval(-12)
            ClimateCommandReceipt(
                sessionScope: scope,
                interactionID: "orig",
                date: originalStart,
                running: true,
                startedAt: originalStart,
                summary: "Climate on.",
                deliveryState: .confirmed
            ).save(vin: Self.vin, group: service.appGroupIdentifier)

            let setTemp = SetCabinTemperatureIntent()
            setTemp.vehicle = Self.vehicle
            setTemp.temperature = Measurement(value: 71, unit: .fahrenheit)
            _ = try await setTemp.perform()

            let updatedReceipt = try #require(
                ClimateCommandReceipt.latest(vin: Self.vin, scope: scope, group: service.appGroupIdentifier)
            )
            let updatedStart = try #require(updatedReceipt.startedAt)
            // Must preserve originalStart rather than resetting startedAt to Date.now.
            #expect(abs(updatedStart.timeIntervalSince(originalStart)) < 0.05)
        }
    }

    @Test func recordClimateControlCreatesReceiptsWithoutPriorSnippet() async throws {
        let nowMS = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Self.tessieVehiclesJSON(hvacOn: true, timestampMS: nowMS))
            case "/VIN-1/status":
                return (200, Self.statusPayload("awake"))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, service, requests in
            let scope = try #require(service.sessionScopeID)
            _ = try await service.vehicles()
            #expect(ClimateCommandReceipt.latest(vin: Self.vin, scope: scope, group: service.appGroupIdentifier) == nil)
            #expect(await service.isClimateLikelyRunning(vin: Self.vin))

            // Stopping climate via ControlCarIntent (no snippet created) must still record running=false.
            let stopControl = ControlCarIntent()
            stopControl.vehicle = Self.vehicle
            let stopChanges = CarControlSettings()
            stopChanges.climateOn = false
            stopControl.changes = stopChanges
            _ = try await stopControl.perform()

            let stopReceipt = try #require(
                ClimateCommandReceipt.latest(vin: Self.vin, scope: scope, group: service.appGroupIdentifier)
            )
            #expect(stopReceipt.running == false)
            #expect(!(await service.isClimateLikelyRunning(vin: Self.vin)))

            // Starting climate via ControlCarIntent (no snippet) records confirmed start so SetCabinTemperature skips start_climate.
            let startControl = ControlCarIntent()
            startControl.vehicle = Self.vehicle
            let startChanges = CarControlSettings()
            startChanges.climateOn = true
            startControl.changes = startChanges
            _ = try await startControl.perform()

            #expect(await service.isClimateLikelyRunning(vin: Self.vin))
            let beforeTemp = requests().count
            let setTemp = SetCabinTemperatureIntent()
            setTemp.vehicle = Self.vehicle
            setTemp.temperature = Measurement(value: 72, unit: .fahrenheit)
            _ = try await setTemp.perform()
            let tempPosts = requests().dropFirst(beforeTemp).filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent }
            #expect(tempPosts == ["set_temperatures"])
        }
    }

    @Test func adjustSnippetClimateAndWidgetUseAsyncWakeForSingleClimateToggles() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/status":
                return (200, Self.statusPayload("asleep"))
            case "/VIN-1/state":
                return (200, Data(#"{"display_name":"Roadrunner"}"#.utf8))
            default:
                return (200, FleetKitFixtures.commandResponse(result: true))
            }
        }) { _, service, requests in
            let scope = try #require(service.sessionScopeID)

            // 1. Snippet "Off" button uses async wake on a sleeping car and saves waking receipt.
            let turnOff = AdjustSnippetClimateIntent(
                vehicle: Self.vehicle,
                targetFahrenheit: nil,
                turnOff: true,
                interactionID: "card-wake",
                scope: scope
            )
            _ = try await turnOff.perform()
            let offPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(offPost.url?.path == "/VIN-1/command/stop_climate")
            #expect(Self.hasAsyncWakeQuery(offPost))
            let offReceipt = try #require(ClimateCommandReceipt.latest(vin: Self.vin, scope: scope, group: service.appGroupIdentifier))
            #expect(offReceipt.isWaking)
            #expect(offReceipt.running == false)

            // 2. Snippet "Turn On" button uses async wake on a sleeping car and keeps startedAt nil.
            let turnOn = AdjustSnippetClimateIntent(
                vehicle: Self.vehicle,
                targetFahrenheit: nil,
                turnOff: false,
                interactionID: "card-wake",
                scope: scope
            )
            _ = try await turnOn.perform()
            let onPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(onPost.url?.path == "/VIN-1/command/start_climate")
            #expect(Self.hasAsyncWakeQuery(onPost))
            let onReceipt = try #require(ClimateCommandReceipt.latest(vin: Self.vin, scope: scope, group: service.appGroupIdentifier))
            #expect(onReceipt.isWaking)
            #expect(onReceipt.startedAt == nil)

            // 3. Widget Start Climate uses async wake on a sleeping car while Lock stays synchronous.
            let widgetClimate = FleetWidgetActionIntent(action: .startClimate, vehicle: Self.vehicle)
            _ = try await widgetClimate.perform()
            let widgetClimatePost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(widgetClimatePost.url?.path == "/VIN-1/command/start_climate")
            #expect(Self.hasAsyncWakeQuery(widgetClimatePost))

            let widgetLock = FleetWidgetActionIntent(action: .lock, vehicle: Self.vehicle)
            _ = try await widgetLock.perform()
            let widgetLockPost = try #require(requests().last(where: { $0.httpMethod == "POST" }))
            #expect(widgetLockPost.url?.path == "/VIN-1/command/lock")
            #expect(!Self.hasAsyncWakeQuery(widgetLockPost))
        }
    }
}
