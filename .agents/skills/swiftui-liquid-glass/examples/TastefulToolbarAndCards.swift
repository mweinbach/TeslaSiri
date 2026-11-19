import SwiftUI

/// Reference screen showing tasteful iOS 27 content-vs-chrome discipline:
/// - Functional toolbar split cleanly with `ToolbarSpacer(.fixed)`
/// - Avatar stripped from shared glass via `.sharedBackgroundVisibility(.hidden)`
/// - Single primary action tinted via `.buttonStyle(.glassProminent)`
/// - Opaque concentric cards (zero glass in content layer) with tabular numerals
/// - iOS 27 universal `.swipeActionsContainer()` and `.reorderContainer()` on `LazyVStack`
@available(iOS 27, *)
struct TastefulToolbarAndCards: View {
    struct FlightLeg: Identifiable, Hashable {
        let id = UUID()
        let code: String
        let route: String
        let departure: String
        let status: Status

        enum Status: String {
            case onTime = "On Time"
            case delayed = "43m late"
        }
    }

    @State private var legs: [FlightLeg] = [
        .init(code: "DL 383", route: "SFO → JFK", departure: "09:10", status: .onTime),
        .init(code: "AA 16", route: "SFO → JFK", departure: "12:43", status: .delayed),
        .init(code: "UA 1387", route: "SFO → IAH", departure: "13:18", status: .onTime)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    // iOS 26/27 HIG: Title-Style Capitalization on section headers
                    Text("Upcoming Flights")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 4)

                    ForEach(legs) { leg in
                        FlightStatusCard(leg: leg)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    legs.removeAll { $0.id == leg.id }
                                }
                                Button("Share", systemImage: "square.and.arrow.up") { }
                                    .tint(.blue)
                            }
                    }
                    .reorderable()
                }
                .padding()
            }
            .swipeActionsContainer()
            .reorderContainer(for: FlightLeg.self) { difference in
                legs.apply(difference: difference)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .navigationTitle("My Flights")
            .toolbar {
                // Neutral monochromatic icon cluster
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Filter", systemImage: "line.3.horizontal.decrease") { }
                    Button("Share", systemImage: "square.and.arrow.up") { }
                }

                // Separate non-glass avatar cleanly from icon glass capsule
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Profile")
                        .sharedBackgroundVisibility(.hidden)
                }

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                // Single accent-tinted primary CTA
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct FlightStatusCard: View {
    let leg: TastefulToolbarAndCards.FlightLeg

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(leg.code)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(leg.route)
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(leg.departure)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(leg.status.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(leg.status == .onTime ? .green : .red)
            }
        }
        .padding(16)
        // Content layer stays solid & legible; ConcentricRectangle matches outer container curvature
        .background(.background.secondary, in: ConcentricRectangle())
    }
}
