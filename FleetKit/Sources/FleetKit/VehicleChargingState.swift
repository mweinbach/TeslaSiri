import AppIntents
import Foundation

/// What the car reports about charging. Tesla's own values are `Charging`, `Starting`,
/// `Complete`, `Stopped`, `NoPower`, and `Disconnected`.
public enum VehicleChargingState: String, AppEnum, Sendable {
    case charging
    case starting
    case complete
    case stopped
    case noPower = "nopower"
    case disconnected

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Charging State")
    public static let caseDisplayRepresentations: [VehicleChargingState: DisplayRepresentation] = [
        .charging: DisplayRepresentation(title: "Charging", subtitle: "Plugged in and adding energy"),
        .starting: DisplayRepresentation(title: "Starting", subtitle: "Plugged in and about to start charging"),
        .complete: DisplayRepresentation(title: "Complete", subtitle: "Plugged in and charged to the limit"),
        .stopped: DisplayRepresentation(title: "Stopped", subtitle: "Plugged in but not charging"),
        .noPower: DisplayRepresentation(title: "No Power", subtitle: "Plugged in, but the charger isn't supplying power"),
        .disconnected: DisplayRepresentation(title: "Disconnected", subtitle: "Not plugged in")
    ]

    /// The state for the provider's wording, or `nil` for a value this app has no case for.
    public init?(reported state: String) {
        self.init(rawValue: state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
