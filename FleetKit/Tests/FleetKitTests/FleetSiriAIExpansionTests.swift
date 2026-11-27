import AppIntents
import Foundation
import Testing
@testable import FleetKit

/// Coverage for the multi-topic vehicle info tool, comfort and charging controls,
/// charge details, software install readiness, and the app's Siri skills bundle.
struct FleetSiriAIExpansionTests {
    private static let richStateJSON = """
    {
      "display_name":"Roadrunner",
      "drive_state":{"latitude":37.3317,"longitude":-122.0301,"speed":0,"shift_state":"P","timestamp":1710000000000},
      "charge_state":{"battery_level":64,"battery_range":201.4,"charge_limit_soc":80,"charging_state":"Charging","charger_power":11,"charge_rate":30,"time_to_full_charge":1.5,"charge_port_door_open":true,"timestamp":1710000000000},
      "climate_state":{"inside_temp":20,"outside_temp":5,"is_climate_on":true,"driver_temp_setting":21,"seat_heater_left":3,"seat_heater_right":0,"steering_wheel_heater":true,"defrost_mode":0,"timestamp":1710000000000},
      "vehicle_state":{"locked":false,"sentry_mode":true,"odometer":12345.6,"df":0,"pf":0,"dr":0,"pr":0,"ft":0,"rt":1,"fd_window":1,"fp_window":0,"rd_window":0,"rp_window":0,"car_version":"2026.2.1 abc","timestamp":1710000000000},
      "gui_settings":{"gui_distance_units":"mi/hr","gui_temperature_units":"F"}
    }
    """

    private static let tiresJSON = """
    {"front_left":42,"front_right":36.6,"rear_left":41.8,"rear_right":42.2,"timestamp":1710000001}
    """

    private static let chargesJSON = """
    {
      "results": [
        {"id":901,"started_at":1710003600,"ended_at":1710005400,"location":"Kettleman City Supercharger","is_supercharger":true,"odometer":12300,"energy_added":44.0,"energy_used":50.0,"miles_added":180,"starting_battery":15,"ending_battery":75,"cost":18.4},
        {"id":900,"started_at":1709900000,"ended_at":1709930000,"location":"Home","is_supercharger":false,"energy_added":20.0,"energy_used":23.0,"miles_added":80,"starting_battery":50,"ending_battery":80}
      ]
    }
    """

    private static func vehicleRouter(state: String = richStateJSON) -> (URLRequest) throws -> (Int, Data) {
        { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state": (200, Data(state.utf8))
            case "/VIN-1/tire_pressure": (200, Data(tiresJSON.utf8))
            case "/VIN-1/charges": (200, Data(chargesJSON.utf8))
            default: (200, FleetKitFixtures.commandResponse(result: true))
            }
        }
    }

    // MARK: - Get Tesla Vehicle Info

    @Test func `vehicle info answers only the requested topics with per-tire PSI`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { _ in
            let intent = GetVehicleInfoIntent(topics: [.battery, .range, .tirePressure, .security])
            let status = try #require(try await intent.perform().value)

            #expect(status.batteryPercent == 64)
            #expect(status.frontRightTirePSI == 36.6)
            #expect(status.temperatureUnit == "°F")
            #expect(status.openClosures == "Trunk, Driver window")
            #expect(status.seatHeaterSummary == "Driver 3, Passenger 0")
            #expect(status.steeringWheelHeaterOn == true)
            #expect(status.minutesToFullCharge == 90)
            #expect(status.gear == "P")

            let answer = status.spokenAnswer(for: [.battery, .range, .tirePressure, .security], now: status.updatedAt ?? .now)
            #expect(answer.contains("64% with about 201 miles of range"))
            #expect(answer.contains("front right 37"))
            #expect(answer.contains("front right tire looks low"))
            #expect(answer.contains("It's unlocked and Sentry Mode is on."))
            #expect(answer.contains("Open: Trunk, Driver window."))
            #expect(!answer.contains("odometer"))
            #expect(!answer.contains("charging"))
        }
    }

    @Test func `vehicle info climate and charging sentences use the car's units`() throws {
        let snapshot = FleetSnapshotInfo(
            vin: "VIN-1",
            batteryLevel: 64,
            chargeLimitSOC: 80,
            chargingState: "Charging",
            chargerPowerKW: 11,
            chargeRateMPH: 30,
            timeToFullCharge: 1.5,
            insideTemp: 68,
            outsideTemp: 41,
            targetTemp: 70,
            hvacOn: true,
            odometer: 12_345.6,
            updatedAt: 1_710_000_000_000,
            temperatureInFahrenheit: true
        )
        let status = VehicleStatusEntity(snapshot: snapshot, vehicleName: "Roadrunner")
        let answer = status.spokenAnswer(for: [.charging, .climate, .odometer], now: status.updatedAt ?? .now)
        #expect(answer.contains("It's charging at 11 kW"))
        #expect(answer.contains("The charge limit is 80%."))
        #expect(answer.contains("It's 68°F inside and 41°F outside."))
        #expect(answer.contains("Climate is on, set to 70°F."))
        #expect(answer.contains("12,346 miles") || answer.contains("12346 miles"))
    }

    @Test func `stale readings are called out`() {
        let snapshot = FleetSnapshotInfo(vin: "VIN-1", batteryLevel: 50, updatedAt: 1_710_000_000_000)
        let status = VehicleStatusEntity(snapshot: snapshot, vehicleName: "Roadrunner")
        let later = Date(timeIntervalSince1970: 1_710_000_000 + 3 * 60 * 60)
        let answer = status.spokenAnswer(for: [.battery], now: later)
        #expect(answer.contains("while the car was asleep"))
    }

    // MARK: - Comfort and charging controls

    @Test func `seat heater steering wheel and charging amps map to Tessie commands`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            let seat = try #require(try await SetSeatClimateIntent(seat: .frontSeats, level: 2).perform().value)
            #expect(seat.action == "set_seat_heat")

            let wheel = SetSteeringWheelHeaterIntent()
            wheel.on = false
            let wheelResult = try #require(try await wheel.perform().value)
            #expect(wheelResult.appliedValue == "off")

            let amps = SetChargingAmpsIntent()
            amps.amps = 16
            let ampsResult = try #require(try await amps.perform().value)
            #expect(ampsResult.appliedValue == "16 A")

            let urls = requests().compactMap { $0.url?.absoluteString }
            #expect(urls.contains { $0.contains("/VIN-1/command/start_climate") })
            #expect(urls.contains { $0.contains("/VIN-1/command/set_seat_heat") && $0.contains("seat=front_left") && $0.contains("level=2") })
            #expect(urls.contains { $0.contains("/VIN-1/command/set_seat_heat") && $0.contains("seat=front_right") && $0.contains("level=2") })
            #expect(urls.contains { $0.contains("/VIN-1/command/stop_steering_wheel_heater") })
            #expect(urls.contains { $0.contains("/VIN-1/command/set_charging_amps") && $0.contains("amps=16") })
        }
    }

    @Test func `one trunk tool opens the rear trunk by default or the frunk`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            #expect(OpenTrunkIntent().trunk == .rear)

            // requestConfirmation needs the App Intents runtime, so exercise the shared
            // path both intents use with confirmation stubbed and recorded.
            var confirmations: [String] = []
            let rear = try await OpenTrunkIntent.open(.rear, vehicle: nil) { dialog in
                confirmations.append(String(describing: dialog))
            }
            #expect(rear.appliedValue == "rear")
            #expect(rear.summary == "Opening the trunk on Roadrunner.")

            let front = try await OpenTrunkIntent.open(.front, vehicle: nil) { dialog in
                confirmations.append(String(describing: dialog))
            }
            #expect(front.appliedValue == "front")
            #expect(front.summary == "Opening the frunk on Roadrunner.")
            #expect(confirmations.count == 2)
            #expect(OpenTrunkIntent(trunk: .front).trunk == .front)

            let paths = requests().compactMap { $0.url?.path }
            #expect(paths.filter { $0 == "/VIN-1/command/activate_rear_trunk" }.count == 1)
            #expect(paths.filter { $0 == "/VIN-1/command/activate_front_trunk" }.count == 1)
        }
    }

    @Test func `rear seat cooling is rejected with a clear message`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            await #expect(throws: FleetKitError.self) {
                try await SetSeatClimateIntent(seat: .rearLeft, level: 2, mode: .cool).perform()
            }
            #expect(!requests().contains { $0.url?.path.contains("/command/") == true })
        }
    }

    @Test func `cabin climate settings apply seat and steering wheel heat`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            let intent = ConfigureCabinClimateIntent()
            intent.settings = CabinClimateSettings(driverSeatHeatLevel: 3, steeringWheelHeat: true)
            let value = try #require(try await intent.perform().value)
            #expect(value.appliedValue?.contains("driver seat heat 3") == true)
            #expect(value.appliedValue?.contains("steering wheel heat on") == true)

            let urls = requests().compactMap { $0.url?.absoluteString }
            #expect(urls.contains { $0.contains("/command/start_climate") })
            #expect(urls.contains { $0.contains("/command/set_seat_heat") && $0.contains("seat=front_left") && $0.contains("level=3") })
            #expect(urls.contains { $0.contains("/command/start_steering_wheel_heater") })
            #expect(!urls.contains { $0.contains("seat=front_right") })
        }
    }

    @Test func `navigation sends the destination with a locale`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            let intent = SendNavigationIntent()
            intent.destination = "1 Infinite Loop, Cupertino"
            _ = try await intent.perform()
            let share = try #require(requests().first { $0.url?.path == "/VIN-1/command/share" })
            let query = URLComponents(url: try #require(share.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first { $0.name == "value" }?.value == "1 Infinite Loop, Cupertino")
            #expect(query.first { $0.name == "locale" }?.value?.isEmpty == false)
        }
    }

    // MARK: - Charging history and details

    @Test func `charge details default to the latest session with efficiency`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { _ in
            let session = try #require(try await GetChargeDetailsIntent().perform().value)
            #expect(session.id == "VIN-1:901")
            #expect(session.isSupercharger)
            #expect(session.energyDrawnKWH == 50)
            #expect(session.chargingEfficiencyPercent == 88)
            #expect(session.location == "Kettleman City Supercharger")
        }
    }

    @Test func `charging history filters by charger type and date`() async throws {
        try await withIsolatedFleetService(responder: Self.vehicleRouter()) { requests in
            let intent = GetRecentChargesIntent()
            intent.count = 5
            intent.superchargersOnly = false
            intent.startDate = Date(timeIntervalSince1970: 1_709_800_000)
            let sessions = try #require(try await intent.perform().value)
            #expect(sessions.map(\.id) == ["VIN-1:900"])

            let chargesRequest = try #require(requests().first { $0.url?.path == "/VIN-1/charges" })
            #expect(chargesRequest.url?.query?.contains("from=1709800000") == true)
        }
    }

    @Test func `charge session entity is indexed without the full VIN`() {
        let info = FleetChargeInfo(
            sessionID: "5YJ3E1EA7KF000316:901",
            vin: "5YJ3E1EA7KF000316",
            startedAt: 1_710_003_600_000,
            endedAt: 1_710_005_400_000,
            location: "Kettleman City Supercharger",
            isSupercharger: true,
            energyAddedKWH: 44,
            milesAdded: 180,
            startingBatteryPercent: 15,
            endingBatteryPercent: 75,
            cost: 18.4
        )
        let entity = ChargeSessionEntity(info: info, vehicleName: "Roadrunner")
        let attributes = entity.attributeSet
        #expect(entity.vehicleName == "Roadrunner")
        #expect(attributes.keywords?.contains("Roadrunner") == true)
        #expect(attributes.contentDescription?.contains("Roadrunner Supercharged") == true)
        #expect(attributes.kind == "Tesla Charging Session")
        #expect(attributes.keywords?.contains("Supercharger") == true)
        #expect(attributes.keywords?.contains("Kettleman City Supercharger") == true)
        #expect(attributes.contentDescription?.contains("15% to 75%") == true)
        #expect(attributes.contentDescription?.contains("5YJ3E1EA7KF000316") == false)
        #expect(attributes.keywords?.contains("5YJ3E1EA7KF000316") == false)
    }

    // MARK: - Vehicle entity

    @Test func `vehicle entity exposes model and paint for disambiguation`() {
        let info = FleetVehicleInfo(vin: "VIN-1", displayName: "Roadrunner", carType: "modely", exteriorColor: "MidnightSilver")
        let entity = VehicleEntity(info: info)
        #expect(entity.model == "Model Y")
        #expect(entity.color == "Midnight Silver")
        #expect(entity.attributeSet.kind == "Model Y")
        #expect(FleetVehicleInfo(vin: "V", displayName: nil, carType: "cybertruck").modelName == "Cybertruck")
        #expect(FleetVehicleInfo(vin: "V", displayName: nil, carType: "model3").modelName == "Model 3")
    }

    // MARK: - Software install readiness

    @Test func `install reports a downloading update instead of scheduling it`() async throws {
        let downloading = Self.richStateJSON.replacingOccurrences(
            of: "\"car_version\":\"2026.2.1 abc\"",
            with: "\"car_version\":\"2026.2.1 abc\",\"software_update\":{\"status\":\"downloading\",\"version\":\"2026.8.4\",\"download_perc\":40}"
        )
        try await withIsolatedFleetService(responder: Self.vehicleRouter(state: downloading)) { requests in
            let result = try #require(try await InstallSoftwareUpdateIntent().perform().value)
            #expect(result.succeeded == false)
            #expect(result.summary.contains("downloading"))
            #expect(result.summary.contains("40%"))
            #expect(!requests().contains { $0.url?.path.contains("schedule_software_update") == true })
        }
    }

    @Test func `software status only treats downloaded updates as installable`() throws {
        let ready = FleetSoftwareInfo(currentVersion: "2026.2.1", availableVersion: "2026.8.4", updateAvailable: true, installable: true, status: "available", downloadPercent: 100, installPercent: nil, expectedDurationMinutes: 25)
        let readyEntity = SoftwareUpdateEntity(info: ready, vin: "VIN-1", vehicleName: "Roadrunner")
        #expect(readyEntity.spokenStatus == "Software update 2026.8.4 is ready to install on Roadrunner. Installing takes about 25 minutes, and the car can't be driven during it.")

        let upToDate = FleetSoftwareInfo(currentVersion: "2026.2.1", availableVersion: nil, updateAvailable: false, installable: false, status: nil, downloadPercent: nil, installPercent: nil, expectedDurationMinutes: nil)
        #expect(SoftwareUpdateEntity(info: upToDate, vin: "VIN-1", vehicleName: "Roadrunner").spokenStatus == "Roadrunner is up to date on 2026.2.1.")
    }

    // MARK: - Skills bundle

    @Test func `app skills bundle follows the Siri skills format`() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FleetKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FleetKit
            .deletingLastPathComponent() // repo root
        let skillsRoot = repoRoot.appending(path: "TeslaSiri/Skills.skillsbundle/Skills", directoryHint: .isDirectory)
        let directories = try FileManager.default.contentsOfDirectory(at: skillsRoot, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        #expect(Set(directories.map(\.lastPathComponent)) == [
            "driving-and-energy-insights", "overnight-security-check", "prepare-trip", "software-update-advisor",
            "vehicle-control"
        ])

        let allTools: [any ToolIntent.Type] = [
            ListCarsIntent.self, GetVehicleInfoIntent.self, GetVehicleStatusIntent.self, LocateCarIntent.self,
            ControlCarIntent.self, UnlockOrOpenCarIntent.self, SetCabinTemperatureIntent.self, SetSeatClimateIntent.self,
            SendNavigationIntent.self, InstallSoftwareUpdateIntent.self, CancelSoftwareUpdateIntent.self,
            FindDrivesIntent.self, GetDriveDetailsIntent.self, GetDrivingStatsIntent.self,
            GetRecentChargesIntent.self, GetChargeDetailsIntent.self, GetChargingStatsIntent.self,
            GetBatteryHealthIntent.self, GetSoftwareStatusIntent.self, GetReleaseNotesIntent.self
        ]
        let toolTitles: Set<String> = allTools.reduce(into: []) {
            $0.insert(String(localized: $1.title))
        }
        #expect(allTools.count == 20)
        #expect(toolTitles.count == allTools.count, "Every @AppIntent(.tool) must have a unique title")

        let namePattern = /^[a-z0-9]+(-[a-z0-9]+)*$/
        for directory in directories {
            let raw = try String(contentsOf: directory.appending(path: "SKILL.md"), encoding: .utf8)
            let lines = raw.components(separatedBy: "\n")
            #expect(lines.first == "---")
            let closing = try #require(lines.dropFirst().firstIndex(of: "---"))
            let frontmatter = lines[1..<closing]
            let fields = Dictionary(uniqueKeysWithValues: frontmatter.compactMap { line -> (String, String)? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                return (String(line[..<colon]), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            })
            #expect(Set(fields.keys) == ["name", "description"], "Only name and description are supported")
            let name = try #require(fields["name"])
            #expect(name == directory.lastPathComponent)
            #expect(name.wholeMatch(of: namePattern) != nil)
            let description = try #require(fields["description"])
            #expect(!description.isEmpty && description.count <= 1024)
            #expect(!description.contains(": "), "An unquoted \": \" breaks the YAML and drops every skill")

            let body = lines[(closing + 1)...].joined(separator: "\n")
            #expect(!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(body.firstMatch(of: /[A-Z][A-Za-z]+Intent\b/) == nil, "Refer to tools by title, not Swift type")

            let referenced = body.matches(of: /the ([A-Z][A-Za-z &]+?) tool/).map { String($0.output.1) }
            #expect(!referenced.isEmpty)
            if name == "vehicle-control" {
                let requiredTools = [
                    ListCarsIntent.title, GetVehicleInfoIntent.title, LocateCarIntent.title, ControlCarIntent.title,
                    UnlockOrOpenCarIntent.title, SetCabinTemperatureIntent.title, SetSeatClimateIntent.title,
                    SendNavigationIntent.title
                ].map { String(localized: $0) }
                #expect(Set(requiredTools).isSubset(of: Set(referenced)))
            }
            for title in referenced {
                #expect(toolTitles.contains(title), "\(name) references unknown tool \"\(title)\"")
            }
        }
    }
}
