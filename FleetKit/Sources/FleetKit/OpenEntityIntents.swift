import AppIntents

/// Open intents let Spotlight/Siri turn indexed FleetKit entities into app
/// launches for the matching content. The app can add scene-level handlers to
/// route these targets to specific tabs or detail views.
@AppIntent(schema: .system.open)
public struct OpenVehicleIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Vehicle"

    @Parameter(title: "Vehicle")
    public var target: VehicleEntity

    public init() {}

    public init(target: VehicleEntity) {
        self.target = target
    }
}

@AppIntent(schema: .system.open)
public struct OpenVehicleStatusIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Vehicle Status"

    @Parameter(title: "Vehicle Status")
    public var target: VehicleStatusEntity

    public init() {}

    public init(target: VehicleStatusEntity) {
        self.target = target
    }
}

@AppIntent(schema: .system.open)
public struct OpenDriveIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Drive"

    @Parameter(title: "Drive")
    public var target: DriveEntity

    public init() {}

    public init(target: DriveEntity) {
        self.target = target
    }
}

@AppIntent(schema: .system.open)
public struct OpenSoftwareUpdateIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Software Update"

    @Parameter(title: "Software Update")
    public var target: SoftwareUpdateEntity

    public init() {}

    public init(target: SoftwareUpdateEntity) {
        self.target = target
    }
}

@AppIntent(schema: .system.open)
public struct OpenReleaseNoteIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Release Note"

    @Parameter(title: "Release Note")
    public var target: ReleaseNoteEntity

    public init() {}

    public init(target: ReleaseNoteEntity) {
        self.target = target
    }
}

@AppIntent(schema: .system.open)
public struct OpenChargeSessionIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Charging Session"

    @Parameter(title: "Charging Session")
    public var target: ChargeSessionEntity

    public init() {}

    public init(target: ChargeSessionEntity) {
        self.target = target
    }
}

#if os(iOS)
extension OpenVehicleIntent: TargetContentProvidingIntent {}
extension OpenVehicleStatusIntent: TargetContentProvidingIntent {}
extension OpenDriveIntent: TargetContentProvidingIntent {}
extension OpenSoftwareUpdateIntent: TargetContentProvidingIntent {}
extension OpenReleaseNoteIntent: TargetContentProvidingIntent {}
extension OpenChargeSessionIntent: TargetContentProvidingIntent {}
#endif
