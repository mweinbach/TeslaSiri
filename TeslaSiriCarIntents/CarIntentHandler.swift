import FleetKit
import Foundation
import Intents
import OSLog

/// SiriKit Car Commands ("Lock my car", "Is my car locked?", "How much charge does my car
/// have?", "Honk my horn") and Maps EV routing (List Cars + power level). The work happens in
/// FleetKit's `SiriCarCommandService` against the provider token mirrored by the app.
final class CarIntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        CarCommandsHandler()
    }
}

final class CarCommandsHandler: NSObject,
    INSetCarLockStatusIntentHandling,
    INGetCarLockStatusIntentHandling,
    INGetCarPowerLevelStatusIntentHandling,
    INActivateCarSignalIntentHandling,
    INListCarsIntentHandling
{
    private static let logger = Logger(subsystem: FleetKitLog.subsystem, category: "SiriCarCommands")

    // MARK: - Car name

    private func resolveCarName(_ name: INSpeakableString?) async -> INSpeakableStringResolutionResult {
        do {
            switch try await SiriCarCommandService().resolveCar(identifier: name?.vocabularyIdentifier, spokenName: name?.spokenPhrase) {
            case .car(let vehicle): return .success(with: Self.speakable(vehicle))
            case .ambiguous(let vehicles): return .disambiguation(with: vehicles.map(Self.speakable))
            case .noMatch: return .unsupported()
            }
        } catch {
            // Sign-in and network failures are reported by handle(), which can offer to open the app.
            return .notRequired()
        }
    }

    private func vehicle(named name: INSpeakableString?) async throws -> FleetVehicleInfo {
        switch try await SiriCarCommandService().resolveCar(identifier: name?.vocabularyIdentifier, spokenName: name?.spokenPhrase) {
        case .car(let vehicle): return vehicle
        case .ambiguous, .noMatch: throw FleetKitError.api("That car isn't on this account.")
        }
    }

    private static func speakable(_ vehicle: FleetVehicleInfo) -> INSpeakableString {
        INSpeakableString(vocabularyIdentifier: vehicle.vin, spokenPhrase: vehicle.name, pronunciationHint: nil)
    }

    /// Missing or rejected credentials need the app; everything else is a plain failure.
    private static func needsApp(_ error: any Error, intent: String) -> Bool {
        logger.error("\(intent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        switch error as? FleetKitError {
        case .notSignedIn, .sessionExpired: return true
        default: return false
        }
    }

    // MARK: - Lock and unlock

    func resolveCarName(for intent: INSetCarLockStatusIntent) async -> INSpeakableStringResolutionResult {
        await resolveCarName(intent.carName)
    }

    func resolveLocked(for intent: INSetCarLockStatusIntent) async -> INBooleanResolutionResult {
        guard let locked = intent.locked else { return .needsValue() }
        return .success(with: locked)
    }

    func handle(intent: INSetCarLockStatusIntent) async -> INSetCarLockStatusIntentResponse {
        guard let locked = intent.locked else { return INSetCarLockStatusIntentResponse(code: .failure, userActivity: nil) }
        do {
            let vehicle = try await vehicle(named: intent.carName)
            let delivery = try await SiriCarCommandService().setLocked(locked, vin: vehicle.vin)
            Self.logger.notice("\(locked ? "Locked" : "Unlocked", privacy: .public) \(FleetKitLog.vin(vehicle.vin), privacy: .public) (\(delivery.rawValue, privacy: .public))")
            return INSetCarLockStatusIntentResponse(code: delivery == .confirmed ? .success : .inProgress, userActivity: nil)
        } catch {
            let code: INSetCarLockStatusIntentResponseCode = Self.needsApp(error, intent: "Set car lock") ? .failureRequiringAppLaunch : .failure
            return INSetCarLockStatusIntentResponse(code: code, userActivity: nil)
        }
    }

    // MARK: - Lock status

    func resolveCarName(for intent: INGetCarLockStatusIntent) async -> INSpeakableStringResolutionResult {
        await resolveCarName(intent.carName)
    }

    func handle(intent: INGetCarLockStatusIntent) async -> INGetCarLockStatusIntentResponse {
        do {
            let vehicle = try await vehicle(named: intent.carName)
            guard let locked = try await SiriCarCommandService().isLocked(vin: vehicle.vin) else {
                return INGetCarLockStatusIntentResponse(code: .failure, userActivity: nil)
            }
            let response = INGetCarLockStatusIntentResponse(code: .success, userActivity: nil)
            response.locked = locked
            return response
        } catch {
            let code: INGetCarLockStatusIntentResponseCode = Self.needsApp(error, intent: "Get car lock status") ? .failureRequiringAppLaunch : .failure
            return INGetCarLockStatusIntentResponse(code: code, userActivity: nil)
        }
    }

    // MARK: - Power level (Siri and Maps)

    func resolveCarName(for intent: INGetCarPowerLevelStatusIntent) async -> INSpeakableStringResolutionResult {
        await resolveCarName(intent.carName)
    }

    func handle(intent: INGetCarPowerLevelStatusIntent) async -> INGetCarPowerLevelStatusIntentResponse {
        do {
            let vehicle = try await vehicle(named: intent.carName)
            let level = try await SiriCarCommandService().powerLevel(vin: vehicle.vin)
            let response = INGetCarPowerLevelStatusIntentResponse(code: .success, userActivity: nil)
            response.carIdentifier = level.vin
            response.chargePercentRemaining = level.chargeFraction.map(Float.init)
            if let range = level.rangeMiles {
                let distance = Measurement(value: range, unit: UnitLength.miles)
                response.distanceRemaining = distance
                response.distanceRemainingElectric = distance
            }
            if let fullRange = level.fullRangeMiles {
                let distance = Measurement(value: fullRange, unit: UnitLength.miles)
                response.maximumDistance = distance
                response.maximumDistanceElectric = distance
            }
            response.charging = level.isCharging
            response.minutesToFull = level.minutesToFull
            if let updatedAt = level.updatedAt {
                response.dateOfLastStateUpdate = Calendar.current.dateComponents(in: .current, from: updatedAt)
            }
            return response
        } catch {
            let code: INGetCarPowerLevelStatusIntentResponseCode = Self.needsApp(error, intent: "Get car power level") ? .failureRequiringAppLaunch : .failure
            return INGetCarPowerLevelStatusIntentResponse(code: code, userActivity: nil)
        }
    }

    // MARK: - Honk and flash

    func resolveCarName(for intent: INActivateCarSignalIntent) async -> INSpeakableStringResolutionResult {
        await resolveCarName(intent.carName)
    }

    func resolveSignals(for intent: INActivateCarSignalIntent) async -> INCarSignalOptionsResolutionResult {
        .success(with: intent.signals.isEmpty ? [.audible, .visible] : intent.signals)
    }

    func handle(intent: INActivateCarSignalIntent) async -> INActivateCarSignalIntentResponse {
        let signals: INCarSignalOptions = intent.signals.isEmpty ? [.audible, .visible] : intent.signals
        do {
            let vehicle = try await vehicle(named: intent.carName)
            let delivery = try await SiriCarCommandService().activateSignals(
                flashLights: signals.contains(.visible),
                honkHorn: signals.contains(.audible),
                vin: vehicle.vin
            )
            let response = INActivateCarSignalIntentResponse(code: delivery == .confirmed ? .success : .inProgress, userActivity: nil)
            response.signals = signals
            return response
        } catch {
            let code: INActivateCarSignalIntentResponseCode = Self.needsApp(error, intent: "Activate car signal") ? .failureRequiringAppLaunch : .failure
            return INActivateCarSignalIntentResponse(code: code, userActivity: nil)
        }
    }

    // MARK: - Maps EV routing

    func handle(intent: INListCarsIntent) async -> INListCarsIntentResponse {
        do {
            let cars = try await SiriCarCommandService().cars()
            let response = INListCarsIntentResponse(code: .success, userActivity: nil)
            response.cars = cars.map { car in
                INCar(
                    carIdentifier: car.vin,
                    displayName: car.displayName,
                    year: car.year,
                    make: car.make,
                    model: car.model,
                    color: nil,
                    headUnit: nil,
                    supportedChargingConnectors: car.chargingPorts.map(Self.connector)
                )
            }
            return response
        } catch {
            let code: INListCarsIntentResponseCode = Self.needsApp(error, intent: "List cars") ? .failureRequiringAppLaunch : .failure
            return INListCarsIntentResponse(code: code, userActivity: nil)
        }
    }

    private static func connector(_ port: SiriCarChargingPort) -> INCar.ChargingConnectorType {
        switch port {
        case .nacsDC: .nacsDC
        case .nacsAC: .nacsAC
        case .ccs2: .ccs2
        case .type2AC: .mennekes
        case .gbtDC: .gbtDC
        case .gbtAC: .gbtAC
        }
    }
}
