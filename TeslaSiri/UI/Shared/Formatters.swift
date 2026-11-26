import CoreLocation
import FleetKit
import Foundation
import MapKit

func formattedNumber(_ value: Double?, fractionLength: Int = 0, suffix: String = "") -> String {
    guard let value else {
        return "--"
    }

    return value.formatted(.number.precision(.fractionLength(fractionLength))) + suffix
}

func prefersMetricUnits(_ units: String?) -> Bool {
    FleetKitFormatting.prefersMetric(units: units)
}

func formattedPercent(_ value: Double?, fractionLength: Int = 0) -> String {
    guard let value else { return "--" }
    return FleetKitFormatting.percent(value, fractionLength: fractionLength)
}

func formattedDistance(miles: Double?, units: String? = nil, fractionLength: Int = 0) -> String {
    guard let miles else { return "--" }
    return FleetKitFormatting.distance(
        miles: miles,
        usesMetric: prefersMetricUnits(units),
        fractionLength: fractionLength
    )
}

func formattedSpeed(mph: Double?, units: String? = nil, fractionLength: Int = 0) -> String {
    guard let mph else { return "--" }
    return FleetKitFormatting.speed(
        mph: mph,
        usesMetric: prefersMetricUnits(units),
        fractionLength: fractionLength
    )
}

func formattedTemperature(_ value: Double?, inFahrenheit: Bool, fractionLength: Int = 0) -> String {
    guard let value else { return "--" }
    return FleetKitFormatting.temperature(value, inFahrenheit: inFahrenheit, fractionLength: fractionLength)
}

func formattedEnergyKWH(_ value: Double?, fractionLength: Int = 1) -> String {
    guard let value else { return "--" }
    return FleetKitFormatting.energyKWH(value, fractionLength: fractionLength)
}

func formattedPowerKW(_ value: Double?, fractionLength: Int = 1) -> String {
    guard let value else { return "--" }
    return FleetKitFormatting.powerKW(value, fractionLength: fractionLength)
}

func formattedTirePressure(psi: Double?, units: String? = nil) -> String {
    guard let psi else { return "--" }
    return FleetKitFormatting.tirePressure(psi: psi, usesMetric: prefersMetricUnits(units))
}

func formattedAmps(_ value: Double?) -> String {
    guard let value else { return "--" }
    return Measurement(value: value, unit: UnitElectricCurrent.amperes).formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
    )
}

func formattedVoltage(_ value: Double?) -> String {
    guard let value else { return "--" }
    return Measurement(value: value, unit: UnitElectricPotentialDifference.volts).formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
    )
}

func formattedDuration(milliseconds: Int64?) -> String {
    guard let milliseconds, milliseconds > 0 else {
        return "--"
    }

    let totalSeconds = Int(milliseconds / 1_000)
    if totalSeconds >= 60 {
        return Duration.seconds(totalSeconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
    }
    return Duration.seconds(totalSeconds).formatted(
        .units(allowed: [.seconds], width: .abbreviated)
    )
}

/// Turns raw backend states such as "In_Progress" or "charging" into localized display labels.
func humanizedStatus(_ raw: String) -> String {
    let normalized = raw
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    switch normalized {
    case "charging":
        return String(localized: "Charging", comment: "Vehicle charging state: actively charging")
    case "complete", "completed":
        return String(localized: "Complete", comment: "Status label: completed")
    case "stopped":
        return String(localized: "Stopped", comment: "Vehicle charging state: stopped")
    case "disconnected":
        return String(localized: "Disconnected", comment: "Vehicle charging state: unplugged")
    case "starting":
        return String(localized: "Starting", comment: "Vehicle charging state: starting")
    case "no power":
        return String(localized: "No power", comment: "Vehicle charging state: plugged in with no power")
    case "in progress":
        return String(localized: "In progress", comment: "Drive or activity status: currently in progress")
    case "available":
        return String(localized: "Available", comment: "Software update status: available")
    case "downloading":
        return String(localized: "Downloading", comment: "Software update status: downloading")
    case "downloading wifi wait":
        return String(localized: "Waiting for Wi-Fi", comment: "Software update status: waiting for Wi-Fi")
    case "installing":
        return String(localized: "Installing", comment: "Software update status: installing")
    case "scheduled":
        return String(localized: "Scheduled", comment: "Software update status: scheduled")
    case "online":
        return String(localized: "Online", comment: "Vehicle connectivity state: online")
    case "asleep":
        return String(localized: "Asleep", comment: "Vehicle connectivity state: asleep")
    case "offline":
        return String(localized: "Offline", comment: "Vehicle connectivity state: offline")
    case "parked":
        return String(localized: "Parked", comment: "Vehicle driving state: parked")
    case "driving":
        return String(localized: "Driving", comment: "Vehicle driving state: driving")
    default:
        guard let first = normalized.first else { return raw }
        return first.uppercased() + normalized.dropFirst()
    }
}

func formattedCoordinate(latitude: Double?, longitude: Double?) -> String {
    guard let latitude, let longitude else {
        return "--"
    }

    let lat = latitude.formatted(.number.precision(.fractionLength(4)))
    let lon = longitude.formatted(.number.precision(.fractionLength(4)))
    return "\(lat), \(lon)"
}

func driveEndpointSummary(_ drive: FleetDriveSession, endpointAddresses: DriveEndpointAddresses?) -> String {
    let startAddress = endpointAddresses?.start ?? drive.startAddress
    let endAddress = endpointAddresses?.end ?? drive.endAddress

    switch (startAddress, endAddress) {
    case let (start?, end?):
        return String(localized: "\(start) to \(end)", comment: "Drive route summary between start and destination addresses")
    case let (start?, nil):
        return String(localized: "From \(start)", comment: "Drive route summary when only the start address is known")
    case let (nil, end?):
        return String(localized: "To \(end)", comment: "Drive route summary when only the destination address is known")
    case (nil, nil):
        return String(localized: "Resolving addresses", comment: "Placeholder while reverse-geocoding drive start and end addresses")
    }
}

func formattedJSONValue(_ value: JSONValue) -> String {
    switch value {
    case .string(let value):
        return value
    case .integer(let value):
        return String(value)
    case .double(let value):
        return value.formatted(.number.precision(.fractionLength(0...3)))
    case .bool(let value):
        return value ? "true" : "false"
    case .array(let values):
        return "[\(values.count) values]"
    case .object(let object):
        return "{\(object.count) fields}"
    case .null:
        return "null"
    }
}

extension FleetRoutePoint {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    nonisolated var coordinateKey: String {
        guard let latitude, let longitude else {
            return "missing"
        }
        let lat = latitude.formatted(.number.precision(.fractionLength(5)))
        let lon = longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(lat),\(lon)"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
