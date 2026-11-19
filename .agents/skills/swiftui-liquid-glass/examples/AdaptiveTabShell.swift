import SwiftUI

/// Reference shell demonstrating tasteful iOS 27 root navigation:
/// - Floating Liquid Glass TabView adapting to iPadOS & iPhone landscape sidebar
/// - Detached trailing `.search` and iOS 27 `.prominent` primary action tab
/// - Collapsing tab bar on scroll with an adaptive bottom accessory (e.g., Now Playing / Live Trip)
/// - Explicit `.scrollEdgeEffectStyle(.soft, for: .bottom)` for iOS 27 card legibility
@available(iOS 27, *)
struct AdaptiveTabShell: View {
    enum Destination: Hashable {
        case today, explore, search, create
    }

    @State private var selection: Destination = .today
    @State private var searchQuery = ""
    @State private var isTrackingLiveSession = true

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: Destination.today) {
                NavigationStack {
                    TodayTimelineScreen()
                }
            }

            Tab("Explore", systemImage: "safari", value: Destination.explore) {
                NavigationStack {
                    ExploreCardsScreen()
                }
            }

            // Detached trailing search pill
            Tab(value: Destination.search, role: .search) {
                NavigationStack {
                    SearchDestinationView(query: $searchQuery)
                }
            }

            // iOS 27: Detach a primary action into its own prominent trailing glass circle
            Tab(value: Destination.create, role: .prominent) {
                NavigationStack {
                    QuickCreateView()
                }
            } label: {
                Label("New", systemImage: "plus")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: isTrackingLiveSession) {
            LiveSessionAccessoryBar()
        }
    }
}

/// Adapts cleanly when the tab bar collapses inline during scrolling.
@available(iOS 26, *)
private struct LiveSessionAccessoryBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane.departure")
                .foregroundStyle(.tint)

            if placement == .inline {
                Text("SFO → JFK · 1h 38m")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DL 383 · San Francisco to New York")
                        .font(.subheadline.weight(.semibold))
                    Text("On Time · Gate B14 · Departs 09:10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

@available(iOS 27, *)
private struct ExploreCardsScreen: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 14) {
                ForEach(0..<12, id: \.self) { idx in
                    // Content cards stay solid/matte — never Liquid Glass
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(idx.isMultiple(of: 2) ? Color.teal.gradient : Color.orange.gradient)
                            .frame(height: 110)

                        Text("Destination \(idx + 1)")
                            .font(.headline)
                        Text("4h 20m direct")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(.background.secondary, in: ConcentricRectangle())
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Explore")
        // Critical on iOS 27: prevents vivid cards from colliding starkly behind bottom glass tab pills
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
    }
}

// Placeholder views for compilation context
@available(iOS 27, *)
private struct TodayTimelineScreen: View {
    var body: some View { Text("Today").navigationTitle("Today") }
}

@available(iOS 27, *)
private struct SearchDestinationView: View {
    @Binding var query: String
    var body: some View {
        ContentUnavailableView.search(text: query)
            .searchable(text: $query, prompt: "Search flights or places")
            .navigationTitle("Search")
    }
}

@available(iOS 27, *)
private struct QuickCreateView: View {
    var body: some View { Text("Create").navigationTitle("New Entry") }
}
