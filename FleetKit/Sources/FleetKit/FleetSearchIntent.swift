import AppIntents

/// Opens TeslaSiri's indexed-content search for a system-provided query.
///
/// Xcode 27 renamed the schema from `.system.search` to
/// `.system.searchInApp`. The app target handles the execution and routes the
/// criteria into `SpotlightDebugSection`.
@AppIntent(schema: .system.searchInApp)
public struct SearchFleetIntent: ShowInAppSearchResultsIntent {
    public static let title: LocalizedStringResource = "Search Wattie"
    public static let searchScopes: [StringSearchScope] = [.general]
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Search")
    public var criteria: StringSearchCriteria

    public init() {}

    public init(criteria: StringSearchCriteria) {
        self.criteria = criteria
    }

#if !os(iOS)
    public func perform() async throws -> some IntentResult {
        .result()
    }
#endif
}

#if os(iOS)
extension SearchFleetIntent: TargetContentProvidingIntent {}
#endif
