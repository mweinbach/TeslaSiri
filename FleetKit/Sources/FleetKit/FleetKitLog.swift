import AppIntents
import Foundation
import OSLog

/// Central OSLog loggers for FleetKit.
///
/// Everything logs under one subsystem so a single Console.app or
/// `log stream` filter captures intent execution, Spotlight indexing, entity
/// queries, and backend traffic from both the app process and the App Intents
/// extension process:
///
///     log stream --level info --predicate 'subsystem == "com.maxweinbach.TeslaSiri"'
public enum FleetKitLog {
    public static let subsystem = "com.maxweinbach.TeslaSiri"

    /// App Intent lifecycle: started / succeeded / failed, plus control runs.
    public static let intents = Logger(subsystem: subsystem, category: "AppIntents")

    /// Spotlight donation, reindexing, and query activity.
    public static let spotlight = Logger(subsystem: subsystem, category: "Spotlight")

    /// HTTP traffic from the intents client (method, path, status, timing).
    public static let client = Logger(subsystem: subsystem, category: "FleetIntentClient")

    static let signposter = OSSignposter(subsystem: subsystem, category: "SiriPerformance")

    /// AppEntity queries and option providers (Siri/Shortcuts resolution).
    public static let entities = Logger(subsystem: subsystem, category: "Entities")

    /// Shortened VIN that is safe to include in public log output.
    public static func vin(_ vin: String) -> String {
        vin.count > 6 ? "…" + vin.suffix(6) : vin
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: ContinuousClock.now) / .milliseconds(1))
    }
}

/// Tracks a single intent `perform()` so every run emits a consistent
/// started / succeeded / failed trail with timing.
///
/// Usage inside `perform()`:
///
///     let log = FleetIntentLog(Self.self, vehicle: vehicle)
///     do {
///         ...
///         log.success("locked \(resolved.name)")
///         return .result(...)
///     } catch {
///         throw log.failure(error)
///     }
public struct FleetIntentLog: Sendable {
    private let name: String
    private let start: ContinuousClock.Instant
    private let interval: OSSignpostIntervalState

    public init(_ intentType: (some AppIntent).Type, vehicle: VehicleEntity? = nil) {
        let name = String(describing: intentType)
        self.name = name
        self.start = ContinuousClock.now
        let signposter = FleetKitLog.signposter
        self.interval = signposter.beginInterval("Intent", id: signposter.makeSignpostID(), "\(name, privacy: .public)")
        let vehicleName = vehicle?.name ?? "default"
        FleetKitLog.intents.notice("\(name, privacy: .public) started (vehicle: \(vehicleName, privacy: .public))")
    }

    public func success(_ detail: String) {
        FleetKitLog.signposter.endInterval("Intent", interval)
        let elapsed = FleetKitLog.milliseconds(since: start)
        FleetKitLog.intents.notice("\(self.name, privacy: .public) succeeded in \(elapsed, privacy: .public) ms — \(detail, privacy: .public)")
    }

    /// Logs the failure and hands the error back so call sites can
    /// `throw log.failure(error)`. User cancellation is logged as a notice,
    /// not an error.
    public func failure(_ error: any Error) -> any Error {
        FleetKitLog.signposter.endInterval("Intent", interval)
        let elapsed = FleetKitLog.milliseconds(since: start)
        if error is CancellationError {
            FleetKitLog.intents.notice("\(self.name, privacy: .public) cancelled after \(elapsed, privacy: .public) ms")
        } else {
            FleetKitLog.intents.error("\(self.name, privacy: .public) failed after \(elapsed, privacy: .public) ms — \(error.localizedDescription, privacy: .public)")
        }
        return error
    }
}
