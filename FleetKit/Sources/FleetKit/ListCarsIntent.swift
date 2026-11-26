import AppIntents
import Foundation

@AppIntent(.tool)
public struct ListCarsIntent: AppIntent {
    public static let title: LocalizedStringResource = "List Cars"
    public static let description = IntentDescription(
        "Lists the user's active cars by name, marks the default car, and returns each vehicle with the controls Wattie can request. Use for questions about available cars or their controls. Pass a returned Vehicle to the Control Car tool to target that car. For a command aimed at the default car, use Control Car directly and omit Vehicle.",
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
                    ? "\(first.name) is your default car."
                    : "Your cars are \(names). \(first.name) is your default car."
            } else {
                summary = "There are no active cars on your account."
            }
            log.success("listed \(cars.count) cars")
            return .result(value: cars, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
