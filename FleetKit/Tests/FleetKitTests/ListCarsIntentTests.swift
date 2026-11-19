import AppIntents
import Foundation
import Testing
@testable import FleetKit

struct ListCarsIntentTests {
    private static let roster = """
        {"results":[
          {"vin":"A","last_state":{"display_name":"Silver","vehicle_config":{"has_seat_cooling":false,"can_actuate_trunks":false}}},
          {"vin":"B","last_state":{"display_name":"Blue","vehicle_config":{"has_seat_cooling":true,"can_accept_navigation_requests":true}}},
          {"vin":"C","last_state":{"display_name":"Red","vehicle_config":{"can_accept_navigation_requests":false}}}
        ]}
        """

    @Test func discoveryReturnsSelectableVehiclesAndUsesOnlyTheRoster() async throws {
        try await withIsolatedFleetService(selectedVIN: "B", responder: { request in
            guard request.httpMethod == "GET", request.url?.path == "/vehicles" else {
                throw FleetKitError.badResponse
            }
            return (200, Data(Self.roster.utf8))
        }) { requests in
            let listed = try #require(try await ListCarsIntent().perform().value)
            #expect(listed.map(\.id) == ["B", "A", "C"])
            #expect(listed.map(\.isDefaultCar) == [true, false, false])
            #expect(listed[0].name == "Blue")
            let controls = try #require(listed[0].controls)
            #expect(controls.contains { $0.contains("target temperature") })
            #expect(controls.contains("Send a navigation destination"))
            #expect(listed[0].additionalControls?.contains("Set Tesla Seat Climate: adjust front seat cooling") == true)
            #expect(listed[1].additionalControls?.contains { $0.contains("cooling") } == false)
            #expect(listed[1].controls?.contains { $0.contains("frunk") } == false)
            #expect(listed[2].controls?.contains { $0.contains("navigation") } == false)
            #expect(listed[2].additionalControls?.contains { $0.contains("navigation") } == false)
            #expect(listed[2].additionalControls?.contains { $0.contains("cooling if equipped") } == true)
            #expect(requests().count == 1)

            let selected = await SelectedVehicleOptionsProvider().defaultResult()
            #expect(selected?.id == listed.first?.id)
            let target = try await FleetIntentService.make().resolvedVehicle(listed[1].id)
            #expect(target.vin == "A")
            #expect(requests().count == 1)
        }
    }

    @Test(arguments: [String?.none, "removed"])
    func defaultsToTheFirstActiveCarWhenThePreferredCarIsAbsent(selectedVIN: String?) async throws {
        try await withIsolatedFleetService(selectedVIN: selectedVIN, responder: { _ in
            (200, Data(Self.roster.utf8))
        }) { requests in
            let cars = try #require(try await ListCarsIntent().perform().value)
            let target = try await FleetIntentService.make().resolvedVehicle(nil)
            #expect(cars.filter { $0.isDefaultCar == true }.map(\.id) == [target.vin])
            #expect(target.vin == "A")
            #expect(requests().count == 1)
        }
    }

    @Test func emptyAccountReturnsAnEmptyList() async throws {
        try await withIsolatedFleetService(responder: { _ in (200, Data(#"{"results":[]}"#.utf8)) }) { requests in
            let cars = try #require(try await ListCarsIntent().perform().value)
            #expect(cars.isEmpty)
            #expect(requests().count == 1)
        }
    }
}
