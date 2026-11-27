import AppIntents
import Foundation

/// Where a software update is in its download and install. The raw values are Tesla's own.
public enum SoftwareUpdateStatus: String, AppEnum, Sendable {
    case available
    case downloading
    case waitingForWiFi = "downloading_wifi_wait"
    case scheduled
    case installing

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Software Update Status")
    public static let caseDisplayRepresentations: [SoftwareUpdateStatus: DisplayRepresentation] = [
        .available: DisplayRepresentation(title: "Available", subtitle: "Downloaded and ready to install"),
        .downloading: DisplayRepresentation(title: "Downloading", subtitle: "Downloading to the car"),
        .waitingForWiFi: DisplayRepresentation(title: "Waiting for Wi-Fi", subtitle: "The download is paused until the car is on Wi-Fi"),
        .scheduled: DisplayRepresentation(title: "Scheduled", subtitle: "Set to install at a chosen time"),
        .installing: DisplayRepresentation(title: "Installing", subtitle: "Installing now; the car can't be driven until it finishes")
    ]

    /// The status for the provider's wording, or `nil` for a value this app has no case for.
    public init?(reported status: String) {
        self.init(rawValue: status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// The status in a word or two, for cards.
    var label: String {
        switch self {
        case .available:
            String(localized: "Available", bundle: .module, comment: "Software update status: ready to install")
        case .scheduled:
            String(localized: "Scheduled", bundle: .module, comment: "Software update status: scheduled to install")
        case .installing:
            String(localized: "Installing", bundle: .module, comment: "Software update status: currently installing")
        case .downloading:
            String(localized: "Downloading", bundle: .module, comment: "Software update status: currently downloading")
        case .waitingForWiFi:
            String(localized: "Waiting for Wi-Fi", bundle: .module, comment: "Software update status: waiting for Wi-Fi to download")
        }
    }
}
