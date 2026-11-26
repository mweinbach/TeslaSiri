import Foundation
import Testing
@testable import FleetKit

struct SiriCarCommandsTests {
    private static let modelThreeVIN = "5YJ3E1EA0RF000001"
    private static let roster = """
        {"results":[
          {"vin":"\(modelThreeVIN)","last_state":{"display_name":"Midnight","vehicle_config":{"car_type":"model3"}}},
          {"vin":"VIN-Y","last_state":{"display_name":"Blue Y","vehicle_config":{"car_type":"modely"}}}
        ]}
        """

    private static func vehicle(_ vin: String, _ name: String, carType: String? = nil) -> FleetVehicleInfo {
        FleetVehicleInfo(vin: vin, displayName: name, carType: carType)
    }

    // MARK: - Name matching

    @Test(arguments: [String?.none, "", "my car", "My Tesla", "the car", "vehicle"])
    func genericNamesSelectTheDefaultCar(spoken: String?) {
        let roster = [Self.vehicle("A", "Midnight"), Self.vehicle("B", "Blue Y")]
        let result = SiriCarCommandService.match(identifier: nil, spokenName: spoken, roster: roster, defaultVehicle: roster[1])
        guard case .car(let car) = result else { Issue.record("Expected the default car"); return }
        #expect(car.vin == "B")
    }

    @Test func namesMatchExactlyPartiallyOrByModel() {
        let roster = [
            Self.vehicle("A", "Midnight", carType: "model3"),
            Self.vehicle("B", "Blue Y", carType: "modely"),
            Self.vehicle("C", "Réd Rocket", carType: "cybertruck")
        ]
        func vin(_ spoken: String, identifier: String? = nil) -> String? {
            if case .car(let car) = SiriCarCommandService.match(identifier: identifier, spokenName: spoken, roster: roster, defaultVehicle: roster[0]) {
                return car.vin
            }
            return nil
        }
        #expect(vin("midnight") == "A")
        #expect(vin("My Blue Y") == "B")
        #expect(vin("red rocket") == "C")
        #expect(vin("Model Y") == "B")
        #expect(vin("Tesla Model 3") == "A")
        #expect(vin("Cybertruck") == "C")
        #expect(vin("ignored", identifier: "C") == "C")
        #expect(vin("Roadster") == nil)
    }

    @Test func duplicateNamesNeedDisambiguationAndOneCarAlwaysMatches() {
        let twins = [Self.vehicle("A", "Tesla Y"), Self.vehicle("B", "Tesla Y")]
        guard case .ambiguous(let options) = SiriCarCommandService.match(identifier: nil, spokenName: "Tesla Y", roster: twins, defaultVehicle: twins[0]) else {
            Issue.record("Expected disambiguation"); return
        }
        #expect(options.map(\.vin) == ["A", "B"])

        let single = [Self.vehicle("A", "Midnight")]
        guard case .car(let car) = SiriCarCommandService.match(identifier: nil, spokenName: "the truck downstairs", roster: single, defaultVehicle: nil) else {
            Issue.record("Expected the only car"); return
        }
        #expect(car.vin == "A")

        guard case .noMatch = SiriCarCommandService.match(identifier: nil, spokenName: "my car", roster: [], defaultVehicle: nil) else {
            Issue.record("Expected no match for an empty roster"); return
        }
    }

    // MARK: - Power level and car list

    @Test func powerLevelReportsFractionRangeAndTimeToFull() {
        let charging = FleetSnapshotInfo(vin: "A", batteryLevel: 80, batteryRangeMiles: 240, chargingState: "Charging", timeToFullCharge: 1.25)
        let level = SiriCarPowerLevel(snapshot: charging)
        #expect(level.chargeFraction == 0.8)
        #expect(level.rangeMiles == 240)
        #expect(level.fullRangeMiles == 300)
        #expect(level.isCharging == true)
        #expect(level.minutesToFull == 75)

        let parked = SiriCarPowerLevel(snapshot: FleetSnapshotInfo(vin: "A", batteryLevel: 0, chargingState: "Disconnected", timeToFullCharge: 2))
        #expect(parked.chargeFraction == 0)
        #expect(parked.fullRangeMiles == nil)
        #expect(parked.isCharging == false)
        #expect(parked.minutesToFull == nil)
    }

    @Test func vinModelYearAndRegionalChargingPorts() {
        #expect(SiriCarDescriptor.modelYear(vin: Self.modelThreeVIN) == "2024")
        #expect(SiriCarDescriptor.modelYear(vin: "7SAYGDEE5SA000001") == "2025")
        #expect(SiriCarDescriptor.modelYear(vin: "VIN-1") == nil)
        #expect(SiriCarChargingPort.ports(forRegion: "us") == [.nacsDC, .nacsAC])
        #expect(SiriCarChargingPort.ports(forRegion: "CN") == [.gbtDC, .gbtAC])
        #expect(SiriCarChargingPort.ports(forRegion: "DE") == [.ccs2, .type2AC])
        #expect(SiriCarChargingPort.ports(forRegion: nil) == [.ccs2, .type2AC])
    }

    @Test func carsListTheDefaultCarFirstWithModelDetails() async throws {
        try await withIsolatedFleetService(selectedVIN: "VIN-Y", responder: { request in
            guard request.url?.path == "/vehicles" else { throw FleetKitError.badResponse }
            return (200, Data(Self.roster.utf8))
        }) { requests in
            let cars = try await SiriCarCommandService().cars(regionCode: "US")
            #expect(cars.map(\.vin) == ["VIN-Y", Self.modelThreeVIN])
            #expect(cars.map(\.displayName) == ["Blue Y", "Midnight"])
            #expect(cars.map(\.model) == ["Model Y", "Model 3"])
            #expect(cars.map(\.year) == [nil, "2024"])
            #expect(cars.allSatisfy { $0.make == "Tesla" && $0.chargingPorts == [.nacsDC, .nacsAC] })
            #expect(requests().count == 1)
        }
    }

    // MARK: - Commands

    @Test func lockStatusAndPowerLevelReadTheNamedCar() async throws {
        let state = """
            {"charge_state":{"battery_level":64,"battery_range":198.4,"charging_state":"Stopped"},"vehicle_state":{"locked":false}}
            """
        try await withIsolatedFleetService(selectedVIN: "VIN-Y", responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(Self.roster.utf8))
            case "/\(Self.modelThreeVIN)/state": (200, Data(state.utf8))
            default: throw FleetKitError.badResponse
            }
        }) { _ in
            let commands = SiriCarCommandService()
            guard case .car(let car) = try await commands.resolveCar(identifier: nil, spokenName: "Midnight") else {
                Issue.record("Expected Midnight"); return
            }
            let locked = try await commands.isLocked(vin: car.vin)
            #expect(locked == false)
            let level = try await commands.powerLevel(vin: car.vin)
            #expect(level.vin == Self.modelThreeVIN)
            #expect(level.chargeFraction == 0.64)
            #expect(level.rangeMiles == 198.4)
            #expect(level.isCharging == false)
        }
    }

    @Test func lockAndSignalsSendOneCommandAtATime() async throws {
        try await withIsolatedFleetService(selectedVIN: "VIN-Y", responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(Self.roster.utf8))
            case "/VIN-Y/status": (200, Data(#"{"status":"awake"}"#.utf8))
            case "/VIN-Y/command/lock", "/VIN-Y/command/flash", "/VIN-Y/command/honk": (200, FleetKitFixtures.commandResponse())
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let commands = SiriCarCommandService()
            let lock = try await commands.setLocked(true, vin: "VIN-Y")
            let signals = try await commands.activateSignals(flashLights: true, honkHorn: true, vin: "VIN-Y")
            #expect(lock == .confirmed)
            #expect(signals == .confirmed)
            let commandPaths = requests().compactMap(\.url?.path).filter { $0.contains("/command/") }
            #expect(commandPaths == ["/VIN-Y/command/lock", "/VIN-Y/command/flash", "/VIN-Y/command/honk"])
        }
    }

    @Test func sleepingCarGetsTheUnlockWithoutWaiting() async throws {
        try await withIsolatedFleetService(selectedVIN: "VIN-Y", responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(Self.roster.utf8))
            case "/VIN-Y/status": (200, Data(#"{"status":"asleep"}"#.utf8))
            case "/VIN-Y/command/unlock": (200, FleetKitFixtures.commandResponse())
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let delivery = try await SiriCarCommandService().setLocked(false, vin: "VIN-Y")
            #expect(delivery == .wakingVehicle)
            let unlock = try #require(requests().first { $0.url?.path == "/VIN-Y/command/unlock" })
            #expect(unlock.url?.query()?.contains("wait_for_completion=false") == true)
        }
    }
}
