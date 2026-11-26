import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FleetKit

struct FleetEntityIndexingTests {
    @Test(arguments: [0, -1])
    func spotlightSearchWithNonpositiveLimitReturnsNoHits(limit: Int) async throws {
        let results = try await FleetSpotlightIndexer.search("Tesla", limit: limit)
        #expect(results.isEmpty)
    }

    @Test(arguments: ["battery car", "status", "missing", ""])
    func statusSearchFetchesOnlyMatchingVehicleStates(query: String) async throws {
        let roster = #"{"results":[{"vin":"A","last_state":{"display_name":"Battery Car"}},{"vin":"B","last_state":{"display_name":"Roadrunner"}}]}"#
        try await withIsolatedFleetService { request in
            switch request.url?.lastPathComponent {
            case "vehicles": (200, Data(roster.utf8))
            case "state": (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            case "tire_pressure": (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
            default: (404, Data())
            }
        } body: { requests in
            let expectedVINs: [String] = switch query {
            case "battery car": ["A"]
            case "missing": []
            default: ["A", "B"]
            }
            let matches = try await VehicleStatusEntityQuery().entities(matching: query)
            #expect(matches.map(\.vin).sorted() == expectedVINs)
            let expectedPaths = ["/vehicles"] + expectedVINs.flatMap { ["/\($0)/state", "/\($0)/tire_pressure"] }
            #expect(requests().compactMap { $0.url?.path }.sorted() == expectedPaths.sorted())
        }
    }

    @Test(arguments: [false, true])
    func savedDriveLookupsSkipUnrelatedVehiclesUnlessALegacyIDIsPresent(includeLegacy: Bool) async throws {
        try await withIsolatedFleetService { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, Data(#"{"results":[{"id":7,"started_at":1710000000}]}"#.utf8))
        } body: { requests in
            var ids = ["VIN-2:7", "OTHER:7", "VIN-2:7"]
            if includeLegacy { ids.append("legacy-drive") }
            let matches = try await DriveEntityQuery().entities(for: ids)
            #expect(matches.map(\.id) == ["VIN-2:7"])
            let expectedPaths = includeLegacy ? ["/vehicles", "/VIN-1/drives", "/VIN-2/drives"] : ["/vehicles", "/VIN-2/drives"]
            #expect(requests().compactMap { $0.url?.path } == expectedPaths)
        }
    }

    @Test func `vehicle entity indexes car control and status keywords`() {
        let entity = VehicleEntity(id: "VIN-1", name: "Roadrunner", model: "Model Y", color: "Pearl White")
        let attributes = entity.attributeSet

        #expect(entity.id == "VIN-1")
        #expect(entity.name == "Roadrunner")
        #expect(attributes.contentDescription?.contains("battery") == true)
        #expect(attributes.contentDescription?.contains("unlock") == true)
        #expect(attributes.title == "Roadrunner")
        #expect(attributes.displayName == "Roadrunner")
        #expect(attributes.kind == "Model Y")
        #expect(attributes.keywords?.contains("Model Y") == true)
        #expect(attributes.keywords?.contains("Pearl White") == true)
        #expect(attributes.keywords?.contains("tire pressure") == true)
        #expect(attributes.keywords?.contains("release notes") == true)
        #expect(attributes.keywords?.contains("unlock") == true)
        #expect(String(localized: entity.displayRepresentation.subtitle!) == "Model Y · Pearl White")
        #expect(VehicleEntity(id: "VIN-1", name: "Roadrunner").attributeSet.kind == "Tesla Vehicle")
    }

    @Test func `vehicle status entity formats mileage tires location and searchable metadata`() throws {
        let snapshot = try FleetKitFixtures.decode(FleetSnapshotInfo.self, from: FleetKitFixtures.snapshotJSON)
        let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: "Roadrunner")
        let attributes = entity.attributeSet

        #expect(entity.id == "status:VIN-1")
        #expect(entity.vin == "VIN-1")
        #expect(entity.batteryPercent == 82)
        #expect(entity.chargeLimitPercent == 90)
        #expect(entity.odometerDisplay == "12,346 mi")
        #expect(entity.statusSummary.contains("Battery 82%"))
        #expect(entity.statusSummary.contains("Odometer 12,346 mi"))
        #expect(entity.statusSummary.contains("Tires FL 39 PSI"))
        #expect(attributes.contentDescription?.contains("Charge limit 90%") == true)
        #expect(attributes.contentDescription?.contains("Speed 41 mph") == true)
        #expect(attributes.title == "Roadrunner Status")
        #expect(attributes.displayName == "Roadrunner vehicle status")
        #expect(attributes.kind == "Tesla Vehicle Status")
        #expect(attributes.textContent?.contains("Charge limit 90%") == true)
        #expect(attributes.keywords?.contains("mileage") == true)
        #expect(attributes.keywords?.contains("PSI") == true)
        #expect(attributes.latitude == NSNumber(value: 37.3317))
        #expect(attributes.longitude == NSNumber(value: -122.0301))
        #expect(attributes.supportsNavigation == NSNumber(value: true))
    }

    @Test func `drive entity indexes distance duration locations and average speed`() throws {
        let drive = try FleetKitFixtures.decode(FleetDriveInfo.self, from: FleetKitFixtures.driveJSON)
        let entity = DriveEntity(info: drive)
        let attributes = entity.attributeSet

        #expect(entity.id == "drive-1")
        #expect(entity.durationMinutes == 31)
        #expect(entity.distanceText == "12.3 mi")
        #expect(entity.routeText == "1 Infinite Loop to 3500 Deer Creek Road")
        #expect(entity.detailText.contains("31 min"))
        #expect(entity.detailText.contains("avg 24 mph"))
        #expect(entity.detailText.contains("max 55 mph"))
        #expect(entity.detailText.contains("3.4 kWh"))
        #expect(attributes.contentDescription?.contains("Tesla drive for vehicle VIN-1") == true)
        #expect(attributes.title?.contains("Tesla Drive") == true)
        #expect(attributes.displayName?.contains("Tesla Drive") == true)
        #expect(attributes.kind == "Tesla Drive")
        #expect(attributes.textContent?.contains("1 Infinite Loop") == true)
        #expect(attributes.keywords?.contains("average speed") == true)
        #expect(attributes.keywords?.contains("1 Infinite Loop") == true)
        #expect(attributes.contentCreationDate == Date(timeIntervalSince1970: 1_710_000_000))
    }

    @Test func `software update entity indexes current available and release versions`() throws {
        let software = try FleetKitFixtures.decode(FleetSoftwareInfo.self, from: FleetKitFixtures.softwareJSON)
        let entity = SoftwareUpdateEntity(info: software, vin: "VIN-1", vehicleName: "Roadrunner")
        let attributes = entity.attributeSet

        #expect(entity.id == "software:VIN-1")
        #expect(entity.vin == "VIN-1")
        #expect(entity.headline == "Update available: 2026.8.4")
        #expect(entity.detailText == "Downloading • 100%")
        #expect(attributes.contentDescription?.contains("Current version 2026.2.1") == true)
        #expect(attributes.contentDescription?.contains("Available version 2026.8.4") == true)
        #expect(attributes.contentDescription?.contains("Installable now") == true)
        #expect(attributes.title == "Roadrunner Software")
        #expect(attributes.displayName == "Roadrunner software update")
        #expect(attributes.kind == "Tesla Software Update")
        #expect(attributes.textContent?.contains("Available version 2026.8.4") == true)
        #expect(attributes.keywords?.contains("release version") == true)
        #expect(attributes.keywords?.contains("2026.8.4") == true)
    }

    @Test func `entity identifiers do not collide across types for the same VIN`() {
        let vehicleID = VehicleEntity(id: "VIN-1", name: "Roadrunner").id
        let statusID = VehicleStatusEntity.entityID(forVIN: "VIN-1")
        let softwareID = SoftwareUpdateEntity.entityID(forVIN: "VIN-1")

        #expect(Set([vehicleID, statusID, softwareID]).count == 3)
    }

    @Test func `legacy bare VIN identifiers still resolve to a VIN`() {
        #expect(VehicleStatusEntity.vin(fromEntityID: "VIN-1") == "VIN-1")
        #expect(VehicleStatusEntity.vin(fromEntityID: "status:VIN-1") == "VIN-1")
        #expect(SoftwareUpdateEntity.vin(fromEntityID: "VIN-1") == "VIN-1")
        #expect(SoftwareUpdateEntity.vin(fromEntityID: "software:VIN-1") == "VIN-1")
    }

    @Test func `release note entity indexes version title and details`() throws {
        let software = try FleetKitFixtures.decode(FleetSoftwareInfo.self, from: FleetKitFixtures.softwareJSON)
        let note = try #require(software.releaseNotes.first)
        let entity = ReleaseNoteEntity(info: note, vin: "VIN-1", version: software.availableVersion)
        let attributes = entity.attributeSet

        #expect(entity.id == "VIN-1:2026.8.4:Better routingNavigation")
        #expect(entity.id == ReleaseNoteEntity.entityID(forVIN: "VIN-1", version: "2026.8.4", noteID: "Better routingNavigation"))
        #expect(entity.title == "Better routing")
        #expect(entity.details == "Route planning improvements")
        #expect(attributes.contentDescription?.contains("Version 2026.8.4") == true)
        #expect(attributes.contentDescription?.contains("Better routing") == true)
        #expect(attributes.title == "Better routing")
        #expect(attributes.displayName == "Better routing 2026.8.4")
        #expect(attributes.kind == "Tesla Release Note")
        #expect(attributes.textContent?.contains("Route planning improvements") == true)
        #expect(attributes.keywords?.contains("release note") == true)
        #expect(attributes.keywords?.contains("Route planning improvements") == true)
    }

    @Test func `indexed metadata avoids full VIN exposure`() throws {
        let vin = "5YJ3E1EA7KF000316"
        let shortenedVIN = FleetKitLog.vin(vin)
        let vehicle = VehicleEntity(id: vin, name: "Roadrunner")
        let longVINDrive = try FleetKitFixtures.decode(
            FleetDriveInfo.self,
            from: FleetKitFixtures.driveJSON.replacingOccurrences(of: "VIN-1", with: vin)
        )

        // Vehicles are told apart by name, model, and paint; no VIN fragment is shown or indexed.
        #expect(String(localized: vehicle.displayRepresentation.subtitle!) == "Tesla")
        #expect(vehicle.attributeSet.contentDescription?.contains(vin) == false)
        #expect(vehicle.attributeSet.keywords?.contains(vin) == false)
        #expect(vehicle.attributeSet.keywords?.contains(shortenedVIN) == false)

        let driveAttributes = DriveEntity(info: longVINDrive).attributeSet
        #expect(driveAttributes.contentDescription?.contains(vin) == false)
        #expect(driveAttributes.contentDescription?.contains(shortenedVIN) == true)
        #expect(driveAttributes.keywords?.contains(vin) == false)
        #expect(driveAttributes.keywords?.contains(shortenedVIN) == true)
    }

    @Test(arguments: ["Roadrunner", "2026.44.1", "software update", "unmatched"])
    func `software update query matches vehicle name, version, and generic terms`(query: String) async throws {
        let stateWithUpdate = """
        {"display_name":"Roadrunner","vehicle_state":{"car_version":"2026.2.1 abc","software_update":{"status":"available","version":"2026.44.1","download_perc":100}}}
        """
        try await withIsolatedFleetService { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state": (200, Data(stateWithUpdate.utf8))
            case "/VIN-2/state": (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            default: (404, Data())
            }
        } body: { _ in
            let matches = try await SoftwareUpdateEntityQuery().entities(matching: query)
            switch query {
            case "Roadrunner", "2026.44.1":
                #expect(matches.map(\.vin) == ["VIN-1"])
            case "software update":
                #expect(Set(matches.map(\.vin)) == ["VIN-1", "VIN-2"])
            default:
                #expect(matches.isEmpty)
            }
        }
    }

    @Test func `indexed entities export plain-text transferable summaries without exposing full VIN`() async throws {
        let vin = "5YJ3E1EA7KF000316"
        let vehicle = VehicleEntity(id: vin, name: "Roadrunner", model: "Model Y", color: "Pearl White")
        let snapshot = FleetSnapshotInfo(vin: vin, batteryLevel: 78, batteryRangeMiles: 245, locked: true, insideTemp: 70, temperatureInFahrenheit: true)
        let status = VehicleStatusEntity(snapshot: snapshot, vehicleName: "Roadrunner", locationAddress: "Cupertino, CA")
        let drive = DriveEntity(info: try FleetKitFixtures.decode(FleetDriveInfo.self, from: FleetKitFixtures.driveJSON.replacingOccurrences(of: "VIN-1", with: vin)))
        let charge = ChargeSessionEntity(info: FleetChargeInfo(
            sessionID: "\(vin):901",
            vin: vin,
            startedAt: 1_710_003_600_000,
            endedAt: 1_710_005_400_000,
            location: "Kettleman City Supercharger",
            isSupercharger: true,
            energyAddedKWH: 44,
            milesAdded: 180,
            startingBatteryPercent: 15,
            endingBatteryPercent: 75,
            cost: 18.4
        ))
        let software = SoftwareUpdateEntity(
            info: try FleetKitFixtures.decode(FleetSoftwareInfo.self, from: FleetKitFixtures.softwareJSON),
            vin: vin,
            vehicleName: "Roadrunner"
        )
        let noteInfo = try #require(try FleetKitFixtures.decode(FleetSoftwareInfo.self, from: FleetKitFixtures.softwareJSON).releaseNotes.first)
        let releaseNote = ReleaseNoteEntity(info: noteInfo, vin: vin, version: "2026.8.4")

        let exportedTexts = try await [
            String(decoding: try await vehicle.exported(as: .plainText), as: UTF8.self),
            String(decoding: try await status.exported(as: .plainText), as: UTF8.self),
            String(decoding: try await drive.exported(as: .plainText), as: UTF8.self),
            String(decoding: try await charge.exported(as: .plainText), as: UTF8.self),
            String(decoding: try await software.exported(as: .plainText), as: UTF8.self),
            String(decoding: try await releaseNote.exported(as: .plainText), as: UTF8.self)
        ]

        #expect(exportedTexts[0] == "Roadrunner (Model Y · Pearl White)")
        #expect(exportedTexts[1].contains("Roadrunner"))
        #expect(exportedTexts[1].contains("Battery 78%"))
        #expect(exportedTexts[2].contains("12.3 mi"))
        #expect(exportedTexts[3].contains("Kettleman City Supercharger"))
        #expect(exportedTexts[4].contains("2026.8.4"))
        #expect(exportedTexts[5].contains("Better routing"))
        for text in exportedTexts {
            #expect(!text.contains(vin))
        }
    }

    @Test func `security-sensitive intents require authentication while everyday warm-up and lock stay lock-screen friendly`() {
        // Physical access, security disablement, and firmware install require authentication.
        #expect(UnlockVehicleIntent.authenticationPolicy == .requiresAuthentication)
        #expect(OpenTrunkIntent.authenticationPolicy == .requiresAuthentication)
        #expect(OpenFrunkIntent.authenticationPolicy == .requiresAuthentication)
        #expect(SetChargePortIntent.authenticationPolicy == .requiresAuthentication)
        #expect(SetSentryModeIntent.authenticationPolicy == .requiresAuthentication)
        #expect(InstallSoftwareUpdateIntent.authenticationPolicy == .requiresAuthentication)

        // Everyday climate/lock commands and non-GPS vehicle status remain usable while locked.
        #expect(ControlCarIntent.authenticationPolicy == .alwaysAllowed)
        #expect(StartClimateIntent.authenticationPolicy == .alwaysAllowed)
        #expect(LockVehicleIntent.authenticationPolicy == .alwaysAllowed)
        #expect(VehicleStatusEntity.authenticationPolicy == .alwaysAllowed)
    }

    @Test func `foreground open and in-app search intents target the main app process`() {
        #expect(SearchFleetIntent.allowedExecutionTargets == .main)
        #expect(OpenVehicleIntent.allowedExecutionTargets == .main)
        #expect(OpenVehicleStatusIntent.allowedExecutionTargets == .main)
        #expect(OpenDriveIntent.allowedExecutionTargets == .main)
        #expect(OpenSoftwareUpdateIntent.allowedExecutionTargets == .main)
        #expect(OpenReleaseNoteIntent.allowedExecutionTargets == .main)
        #expect(OpenChargeSessionIntent.allowedExecutionTargets == .main)
    }

    @Test func `Siri AI tools, snippet intents, and entity queries route to the right execution targets`() {
        let appAndExtension: IntentExecutionTargets = [.main, .appIntentsExtension]

        // All 18 @AppIntent(.tool) intents avoid the WidgetKit extension.
        #expect(ListCarsIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetVehicleInfoIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetVehicleStatusIntent.allowedExecutionTargets == appAndExtension)
        #expect(ControlCarIntent.allowedExecutionTargets == appAndExtension)
        #expect(SetCabinTemperatureIntent.allowedExecutionTargets == appAndExtension)
        #expect(SetSeatClimateIntent.allowedExecutionTargets == appAndExtension)
        #expect(SendNavigationIntent.allowedExecutionTargets == appAndExtension)
        #expect(InstallSoftwareUpdateIntent.allowedExecutionTargets == appAndExtension)
        #expect(CancelSoftwareUpdateIntent.allowedExecutionTargets == appAndExtension)
        #expect(FindDrivesIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetDriveDetailsIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetDrivingStatsIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetRecentChargesIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetChargeDetailsIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetChargingStatsIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetBatteryHealthIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetSoftwareStatusIntent.allowedExecutionTargets == appAndExtension)
        #expect(GetReleaseNotesIntent.allowedExecutionTargets == appAndExtension)

        // Interactive & status snippet intents stay in app + AppIntents extension.
        #expect(DriveRouteSnippetIntent.allowedExecutionTargets == appAndExtension)
        #expect(VehicleStatusSnippetIntent.allowedExecutionTargets == appAndExtension)
        #expect(ChargeSessionSnippetIntent.allowedExecutionTargets == appAndExtension)
        #expect(ClimateControlSnippetIntent.allowedExecutionTargets == appAndExtension)
        #expect(ToggleSnippetMapStyleIntent.allowedExecutionTargets == appAndExtension)
        #expect(SelectSnippetItemIntent.allowedExecutionTargets == appAndExtension)
        #expect(AdjustSnippetClimateIntent.allowedExecutionTargets == appAndExtension)

        // Entity queries: only VehicleEntityQuery runs in WidgetKit.
        #expect(VehicleEntityQuery.allowedExecutionTargets == [.main, .appIntentsExtension, .widgetKitExtension])
        #expect(VehicleStatusEntityQuery.allowedExecutionTargets == appAndExtension)
        #expect(DriveEntityQuery.allowedExecutionTargets == appAndExtension)
        #expect(ChargeSessionEntityQuery.allowedExecutionTargets == appAndExtension)
        #expect(SoftwareUpdateEntityQuery.allowedExecutionTargets == appAndExtension)
        #expect(ReleaseNoteEntityQuery.allowedExecutionTargets == appAndExtension)

        // Widget action intent prefers the WidgetKit extension.
        #expect(FleetWidgetActionIntent.allowedExecutionTargets == [.widgetKitExtension, .appIntentsExtension, .main])
    }

    @Test func `user-facing fleet entities provide card snippets`() {
        func assertSnippetRepresentable<E: SnippetRepresentableEntity>(_ type: E.Type) {
            _ = E.snippet
        }
        assertSnippetRepresentable(VehicleEntity.self)
        assertSnippetRepresentable(VehicleStatusEntity.self)
        assertSnippetRepresentable(DriveEntity.self)
        assertSnippetRepresentable(ChargeSessionEntity.self)
        assertSnippetRepresentable(SoftwareUpdateEntity.self)
        assertSnippetRepresentable(ReleaseNoteEntity.self)
        assertSnippetRepresentable(DrivingStatsEntity.self)
        assertSnippetRepresentable(ChargingStatsEntity.self)
        assertSnippetRepresentable(BatteryHealthEntity.self)
    }
}
