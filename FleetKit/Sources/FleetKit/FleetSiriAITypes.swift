import AppIntents
import Foundation

/// Whether a vehicle command completed while the car was awake or was dispatched
/// asynchronously so the provider can wake a sleeping car and apply it.
public enum VehicleCommandDeliveryState: String, AppEnum, Codable, Sendable {
    case confirmed
    case wakingVehicle

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Command Delivery State")
    public static let caseDisplayRepresentations: [VehicleCommandDeliveryState: DisplayRepresentation] = [
        .confirmed: DisplayRepresentation(
            title: "Confirmed",
            subtitle: "The car was awake and the provider confirmed the command"
        ),
        .wakingVehicle: DisplayRepresentation(
            title: "Waking Vehicle",
            subtitle: "The car was asleep; the provider accepted the request to wake it and apply the command"
        )
    ]

    /// The spoken summary for a command. When the provider accepted the command before a
    /// sleeping car woke, says so instead of claiming the change already happened.
    /// - Parameters:
    ///   - wakingAction: What the request will do once the car wakes, phrased to follow
    ///     "sent the request to wake it and", for example "turn off climate".
    ///   - confirmed: The sentence to use when the car already acknowledged the command.
    func summary(vehicleName: String, wakingAction: String, confirmed: String) -> String {
        switch self {
        case .wakingVehicle: "\(vehicleName) was asleep — sent the request to wake it and \(wakingAction)."
        case .confirmed: confirmed
        }
    }
}

/// Structured result returned by every vehicle command and software action tool
/// so Siri AI and Shortcuts receive machine-readable confirmation alongside
/// spoken dialog.
public struct VehicleCommandResultEntity: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Vehicle Command Result")

    /// Display name of the vehicle that accepted the command.
    @Property(title: "Vehicle Name", description: "The owner's name for the car that received the command.")
    public var vehicleName: String

    /// Full 17-character VIN (or account identifier) of the vehicle.
    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    /// Machine-readable command identifier (for example `door_lock` or `set_charge_limit`).
    @Property(title: "Action", description: "Which command ran, such as door_lock, set_temps, or navigation_request.")
    public var action: String

    /// Whether the connected provider accepted the command for delivery to the vehicle.
    @Property(title: "Succeeded", description: "Whether the vehicle provider accepted the command. Check Delivery State to see whether the car already confirmed it or is waking from sleep.")
    public var succeeded: Bool

    /// Whether the car already confirmed the command or is waking from sleep while the provider applies it.
    @Property(title: "Delivery State", description: "Confirmed when the car already acknowledged the command, or Waking Vehicle when the car was asleep and the provider accepted the request to wake it and apply the change.")
    public var deliveryState: VehicleCommandDeliveryState

    /// Optional human-readable target value applied by the command (such as `"80%"` or `"70°F (21.1°C)"`).
    @Property(title: "Applied Value", description: "The value the command set, such as \"80%\" or \"21.5°C\". Empty for commands without a value.")
    public var appliedValue: String?

    /// Concise summary suitable for multi-step Siri AI reasoning and Shortcuts chaining.
    @Property(title: "Summary", description: "One sentence describing what happened, suitable to tell the user.")
    public var summary: String

    /// Timestamp when the command completed.
    @Property(title: "Executed At", description: "When the command ran.")
    public var executedAt: Date

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(summary)",
            subtitle: "\(vehicleName)"
        )
    }

    public init() {
        self.vehicleName = ""
        self.vin = ""
        self.action = ""
        self.succeeded = false
        self.deliveryState = .confirmed
        self.appliedValue = nil
        self.summary = ""
        self.executedAt = .now
    }

    public init(
        vehicle: FleetVehicleInfo,
        action: String,
        succeeded: Bool = true,
        deliveryState: VehicleCommandDeliveryState = .confirmed,
        appliedValue: String? = nil,
        summary: String,
        executedAt: Date = .now
    ) {
        self.vehicleName = vehicle.name
        self.vin = vehicle.vin
        self.action = action
        self.succeeded = succeeded
        self.deliveryState = deliveryState
        self.appliedValue = appliedValue
        self.summary = summary
        self.executedAt = executedAt
    }
}

/// Composite cabin climate settings Siri writes from requests such as
/// "warm my car to 72 with the seat heater on high and defrost the windshield".
@AppEntity(.generable)
public struct CabinClimateSettings: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cabin Climate Settings")

    @Property(
        title: "Target Temperature (°C)",
        description: "Cabin temperature to heat or cool to, in degrees Celsius from 15 to 28, such as 21.5. Convert Fahrenheit with (°F − 32) × 5 ⁄ 9. Leave empty to keep the current setpoint."
    )
    public var targetTemperatureCelsius: Double?

    @Property(
        title: "Max Defrost",
        description: "true to turn on max defrost for an icy or fogged windshield, false to turn it off. Leave empty to leave defrost unchanged."
    )
    public var enableMaxDefrost: Bool?

    @Property(
        title: "Driver Seat Heat",
        description: "Driver seat heater level from 0 (off) to 3 (high), such as 3 for \"heat my seat\". Leave empty to leave it unchanged."
    )
    public var driverSeatHeatLevel: Int?

    @Property(
        title: "Passenger Seat Heat",
        description: "Front passenger seat heater level from 0 (off) to 3 (high). Leave empty to leave it unchanged."
    )
    public var passengerSeatHeatLevel: Int?

    @Property(
        title: "Steering Wheel Heater",
        description: "true to turn on the heated steering wheel, false to turn it off. Leave empty to leave it unchanged. Not every Tesla has one."
    )
    public var steeringWheelHeat: Bool?

    @Property(
        title: "Dog Mode",
        description: "true to turn on Dog Mode, which keeps the cabin comfortable for a pet and shows a message on the screen; false to turn it off (the user is asked to confirm). Leave empty to leave it unchanged."
    )
    public var enablePetMode: Bool?

    @Property(
        title: "Bioweapon Defense Mode",
        description: "true to turn on Bioweapon Defense Mode (HEPA filtration with positive cabin pressure) for smoke, pollen, or bad air; false to turn it off. Leave empty to leave it unchanged. Only on cars with a HEPA filter."
    )
    public var enableBioweaponDefenseMode: Bool?

    public var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let targetTemperatureCelsius {
            parts.append(String(format: "%.1f°C", targetTemperatureCelsius))
        }
        if let enableMaxDefrost {
            parts.append(enableMaxDefrost ? "Defrost On" : "Defrost Off")
        }
        if let driverSeatHeatLevel {
            parts.append(driverSeatHeatLevel > 0 ? "Driver Seat \(driverSeatHeatLevel)" : "Driver Seat Off")
        }
        if let passengerSeatHeatLevel {
            parts.append(passengerSeatHeatLevel > 0 ? "Passenger Seat \(passengerSeatHeatLevel)" : "Passenger Seat Off")
        }
        if let steeringWheelHeat {
            parts.append(steeringWheelHeat ? "Wheel Heat On" : "Wheel Heat Off")
        }
        if let enablePetMode {
            parts.append(enablePetMode ? "Dog Mode On" : "Dog Mode Off")
        }
        if let enableBioweaponDefenseMode {
            parts.append(enableBioweaponDefenseMode ? "Bioweapon Defense On" : "Bioweapon Defense Off")
        }
        let summary = parts.isEmpty ? "Start Cabin Climate" : parts.joined(separator: " • ")
        return DisplayRepresentation(title: "\(summary)")
    }

    public init() {}

    public init(
        targetTemperatureCelsius: Double? = nil,
        enableMaxDefrost: Bool? = nil,
        driverSeatHeatLevel: Int? = nil,
        passengerSeatHeatLevel: Int? = nil,
        steeringWheelHeat: Bool? = nil,
        enablePetMode: Bool? = nil,
        enableBioweaponDefenseMode: Bool? = nil
    ) {
        self.targetTemperatureCelsius = targetTemperatureCelsius
        self.enableMaxDefrost = enableMaxDefrost
        self.driverSeatHeatLevel = driverSeatHeatLevel
        self.passengerSeatHeatLevel = passengerSeatHeatLevel
        self.steeringWheelHeat = steeringWheelHeat
        self.enablePetMode = enablePetMode
        self.enableBioweaponDefenseMode = enableBioweaponDefenseMode
    }
}

/// Sort order applied to drive search results in `FindDrivesIntent`.
public enum DriveSortOrder: String, AppEnum, Sendable {
    case mostRecent
    case longestDistance
    case longestDuration
    case highestEnergy
    case bestEfficiency

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drive Sort Order")
    public static let caseDisplayRepresentations: [DriveSortOrder: DisplayRepresentation] = [
        .mostRecent: DisplayRepresentation(title: "Most Recent", subtitle: "Newest drives first"),
        .longestDistance: DisplayRepresentation(title: "Longest Distance", subtitle: "Most miles first"),
        .longestDuration: DisplayRepresentation(title: "Longest Duration", subtitle: "Most time behind the wheel first"),
        .highestEnergy: DisplayRepresentation(title: "Most Energy Used", subtitle: "Most kWh first"),
        .bestEfficiency: DisplayRepresentation(title: "Best Efficiency", subtitle: "Lowest Wh/mi first")
    ]
}

/// Composite search filter synthesized by Siri AI when searching drive history by
/// destination/origin text, date range, tag, trip distance, duration, or sort order.
@AppEntity(.generable)
public struct DriveFilterCriteria: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drive Filter Criteria")

    @Property(title: "Location Query", description: "Text to match against where a drive started OR ended, such as \"Airport\" or \"Deer Creek\". Use only when the user names a place without saying whether it was the start or the destination.")
    public var locationQuery: String?

    @Property(title: "Start Location Query", description: "Text to match against where a drive started, such as \"Home\" for \"drives from home\" or \"Palo Alto\".")
    public var startLocationQuery: String?

    @Property(title: "Destination Query", description: "Text to match against where a drive ended, such as \"Tahoe\" for \"when did I last drive to Tahoe?\".")
    public var endLocationQuery: String?

    @Property(title: "Drive Tag", description: "A drive tag to match, such as \"Work\" or \"Commute\". Leave empty for all drives.")
    public var tagQuery: String?

    @Property(title: "Start Date", description: "Earliest start time to include, in the user’s time zone. For \"yesterday\" use the start of yesterday. Leave empty for no lower limit.")
    public var startDate: Date?

    @Property(title: "End Date", description: "Latest start time to include, in the user’s time zone. For \"yesterday\" use the end of yesterday. Leave empty for up to now.")
    public var endDate: Date?

    @Property(title: "Minimum Distance (Miles)", description: "Only include drives at least this long, in miles, such as 10.")
    public var minimumDistanceMiles: Double?

    @Property(title: "Maximum Distance (Miles)", description: "Only include drives at most this long, in miles, such as 5 for short errands.")
    public var maximumDistanceMiles: Double?

    @Property(title: "Minimum Duration (Minutes)", description: "Only include drives that lasted at least this many minutes, such as 30.")
    public var minimumDurationMinutes: Int?

    @Property(title: "Sort By", description: "How to order the results. Leave empty for most recent first.")
    public var sortBy: DriveSortOrder?

    @Property(title: "Maximum Results", description: "How many drives to return, from 1 to 50. Leave empty for 10.")
    public var maximumResults: Int?

    public var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let locationQuery, !locationQuery.isEmpty {
            parts.append("Near \"\(locationQuery)\"")
        }
        if let startLocationQuery, !startLocationQuery.isEmpty {
            parts.append("From \"\(startLocationQuery)\"")
        }
        if let endLocationQuery, !endLocationQuery.isEmpty {
            parts.append("To \"\(endLocationQuery)\"")
        }
        if let tagQuery, !tagQuery.isEmpty {
            parts.append("Tag \"\(tagQuery)\"")
        }
        if let minimumDistanceMiles {
            parts.append(String(format: "≥ %.1f mi", minimumDistanceMiles))
        }
        if let minimumDurationMinutes {
            parts.append("≥ \(minimumDurationMinutes) min")
        }
        if let maximumResults {
            parts.append("Up to \(maximumResults)")
        }
        let title = parts.isEmpty ? "Recent Drives" : parts.joined(separator: " • ")
        return DisplayRepresentation(title: "\(title)")
    }

    public init() {}

    public init(
        locationQuery: String? = nil,
        startLocationQuery: String? = nil,
        endLocationQuery: String? = nil,
        tagQuery: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        minimumDistanceMiles: Double? = nil,
        maximumDistanceMiles: Double? = nil,
        minimumDurationMinutes: Int? = nil,
        sortBy: DriveSortOrder? = nil,
        maximumResults: Int? = nil
    ) {
        self.locationQuery = locationQuery
        self.startLocationQuery = startLocationQuery
        self.endLocationQuery = endLocationQuery
        self.tagQuery = tagQuery
        self.startDate = startDate
        self.endDate = endDate
        self.minimumDistanceMiles = minimumDistanceMiles
        self.maximumDistanceMiles = maximumDistanceMiles
        self.minimumDurationMinutes = minimumDurationMinutes
        self.sortBy = sortBy
        self.maximumResults = maximumResults
    }
}
