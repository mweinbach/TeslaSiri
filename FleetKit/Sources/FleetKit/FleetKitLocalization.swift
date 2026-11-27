import Foundation

/// Bundle description pointing `LocalizedStringResource` and `IntentDialog` instances
/// created inside `FleetKit` at the Swift package's resource bundle (`Bundle.module`).
public enum FleetKitLocalization {
    public static var bundleDescription: LocalizedStringResource.BundleDescription {
        .atURL(Bundle.module.bundleURL)
    }
}

/// Locale-aware measurement, unit, number, and duration formatters for FleetKit
/// intents, entities, widgets, and Siri snippets.
public enum FleetKitFormatting {
    /// Returns true when the vehicle/user prefers metric units, falling back to the
    /// current locale's measurement system when `units` is unspecified.
    public static func prefersMetric(units: String? = nil, locale: Locale = .current) -> Bool {
        if let units {
            return units.lowercased() == "metric"
        }
        return locale.measurementSystem == .metric
    }

    public static func percent(_ value: Double, fractionLength: Int = 0) -> String {
        (value / 100.0).formatted(.percent.precision(.fractionLength(fractionLength)))
    }

    public static func percent(_ value: Int) -> String {
        (Double(value) / 100.0).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Formats a distance stored in miles using miles or kilometers according to car units / locale.
    public static func distance(
        miles: Double,
        usesMetric: Bool? = nil,
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated,
        fractionLength: Int = 0
    ) -> String {
        let metric = usesMetric ?? prefersMetric()
        let base = Measurement(value: miles, unit: UnitLength.miles)
        let target: Measurement<UnitLength> = metric ? base.converted(to: .kilometers) : base
        return target.formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
        )
    }

    /// Formats a speed stored in mph using mph or km/h according to car units / locale.
    public static func speed(
        mph: Double,
        usesMetric: Bool? = nil,
        width: Measurement<UnitSpeed>.FormatStyle.UnitWidth = .abbreviated,
        fractionLength: Int = 0
    ) -> String {
        let metric = usesMetric ?? prefersMetric()
        let base = Measurement(value: mph, unit: UnitSpeed.milesPerHour)
        let target: Measurement<UnitSpeed> = metric ? base.converted(to: .kilometersPerHour) : base
        return target.formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
        )
    }

    /// Formats a temperature already converted to the vehicle's display scale.
    public static func temperature(
        _ value: Double,
        inFahrenheit: Bool,
        width: Measurement<UnitTemperature>.FormatStyle.UnitWidth = .abbreviated,
        fractionLength: Int = 0
    ) -> String {
        let measurement = Measurement<UnitTemperature>(
            value: value,
            unit: inFahrenheit ? .fahrenheit : .celsius
        )
        return measurement.formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
        )
    }

    /// Formats energy in kilowatt-hours.
    public static func energyKWH(_ value: Double, fractionLength: Int = 1) -> String {
        Measurement(value: value, unit: UnitEnergy.kilowattHours).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
        )
    }

    /// Formats power in kilowatts.
    public static func powerKW(
        _ value: Double,
        width: Measurement<UnitPower>.FormatStyle.UnitWidth = .abbreviated,
        fractionLength: Int = 1
    ) -> String {
        Measurement(value: value, unit: UnitPower.kilowatts).formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
        )
    }

    /// Formats tire pressure stored in PSI, converting to bar for metric cars/locales.
    public static func tirePressure(
        psi: Double,
        usesMetric: Bool? = nil,
        fractionLength: Int? = nil
    ) -> String {
        let metric = usesMetric ?? prefersMetric()
        let base = Measurement(value: psi, unit: UnitPressure.poundsForcePerSquareInch)
        let target: Measurement<UnitPressure> = metric ? base.converted(to: .bars) : base
        let digits = fractionLength ?? (metric ? 1 : 0)
        return target.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(digits))
            )
        )
    }

    /// Formats electric current in amperes.
    public static func amps(_ value: Int) -> String {
        Measurement(value: Double(value), unit: UnitElectricCurrent.amperes).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
        )
    }

    /// Formats a duration given in whole minutes using locale-aware units.
    public static func durationMinutes(
        _ minutes: Int,
        width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated
    ) -> String {
        Duration.seconds(max(0, minutes) * 60).formatted(
            .units(allowed: [.hours, .minutes], width: width)
        )
    }
}
