import AppIntents
import Foundation

@AppIntent(.tool)
public struct ListCarsIntent: AppIntent {
    public static let title: LocalizedStringResource = "List Cars"
    public static let description = IntentDescription(
        "Lists the user's active cars by name, marks the default car, and returns each car's available controls. Pass a returned Vehicle to Control Car to target it, or omit Vehicle in Control Car to target the default car.",
        searchKeywords: ["my cars", "my fleet", "which car", "default car", "available controls"]
    )
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[VehicleEntity]> & ProvidesDialog {
        let log = FleetIntentLog(Self.self)
        do {
            let cars = try await VehicleEntity.defaultQuery.allEntities()
            let summary: String
            if let first = cars.first {
                let names = cars.map(\.name).formatted(.list(type: .and))
                summary = cars.count == 1
                    ? String(
                        localized: "\(first.name) is your default car.",
                        bundle: .module,
                        comment: "Siri spoken summary when the user has a single active car. Placeholder is the car name."
                    )
                    : String(
                        localized: "Your cars are \(names). \(first.name) is your default car.",
                        bundle: .module,
                        comment: "Siri spoken summary listing multiple cars. First placeholder is the formatted list of car names, second is the default car name."
                    )
            } else {
                summary = String(
                    localized: "There are no active cars on your account.",
                    bundle: .module,
                    comment: "Siri spoken summary when no active vehicles are found."
                )
            }
            log.success("listed \(cars.count) cars")
            return .result(value: cars, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
