import SwiftUI

/// Reference iPadOS 27 & universal adaptive workspace demonstrating:
/// - `NavigationSplitView` floating translucent glass sidebar with collapsible sections
/// - `.backgroundExtensionEffect()` mirroring hero atmosphere cleanly behind sidebar & inspector
/// - Trailing `.inspector(isPresented:)` for secondary metadata without modal obstruction
/// - Responsive `GridItem(.adaptive)` bento modules (zero `userInterfaceIdiom` checks)
/// - `@Environment(\.appearsActive)` multi-window focus awareness + `.commands` system menu bar
@available(iOS 27, *)
struct AdaptiveWorkspaceApp: App {
    @FocusedValue(\.workspaceActions) private var actions

    var body: some Scene {
        WindowGroup {
            AdaptiveWorkspaceScene()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Station", systemImage: "plus") {
                    actions?.addStation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Workspace") {
                Button("Toggle Inspector", systemImage: "sidebar.right") {
                    actions?.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

struct WorkspaceActions {
    let addStation: () -> Void
    let toggleInspector: () -> Void
}

extension FocusedValues {
    @Entry var workspaceActions: WorkspaceActions?
}

@available(iOS 27, *)
struct AdaptiveWorkspaceScene: View {
    struct Station: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let tideHeight: String
        let status: String
    }

    @State private var stations: [Station] = [
        .init(name: "Chatham, Stage Harbor", tideHeight: "1.9'", status: "Low Tide at 1:50p"),
        .init(name: "Tulalip Bay", tideHeight: "4.4'", status: "High Tide at 12:56p"),
        .init(name: "Mavericks", tideHeight: "5.4'", status: "Low Tide at 12:56p")
    ]
    @State private var selectedStation: Station?
    @State private var searchQuery = ""
    @State private var showInspector = false
    @Environment(\.appearsActive) private var appearsActive

    private var filteredStations: [Station] {
        guard !searchQuery.isEmpty else { return stations }
        return stations.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedStation) {
                Section("Recents") {
                    ForEach(filteredStations) { station in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.name)
                                    .font(.subheadline.weight(.medium))
                                Text(station.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Text(station.tideHeight)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .tag(station)
                    }
                }
            }
            .navigationTitle("Stations")
            .searchable(text: $searchQuery, prompt: "Search stations")
        } detail: {
            StationDashboardDetail(
                station: selectedStation ?? stations[0],
                appearsActive: appearsActive,
                showInspector: $showInspector
            )
        }
        .inspector(isPresented: $showInspector) {
            StationInspectorPanel(station: selectedStation ?? stations[0])
                .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
        }
        .focusedSceneValue(
            \.workspaceActions,
            WorkspaceActions(
                addStation: { },
                toggleInspector: { showInspector.toggle() }
            )
        )
    }
}

@available(iOS 27, *)
private struct StationDashboardDetail: View {
    let station: AdaptiveWorkspaceScene.Station
    let appearsActive: Bool
    @Binding var showInspector: Bool

    private let bentoColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 400), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // Atmospheric twilight gradient extends behind floating sidebar & inspector
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.12, blue: 0.22), Color(red: 0.10, green: 0.20, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .backgroundExtensionEffect()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Fluid adaptive bento grid — automatically reflows across continuous iPad window sizes
                    LazyVGrid(columns: bentoColumns, spacing: 16) {
                        BentoMetricCard(title: "Falling Tide", value: station.tideHeight, footnote: station.status)
                        BentoMetricCard(title: "Sunset", value: "7:48p", footnote: "Sunrise 5:23a")
                        BentoMetricCard(title: "Moonset", value: "1:56p", footnote: "Waning Crescent")
                        BentoMetricCard(title: "Wind", value: "13 km/h", footnote: "WSW · Gust 25 km/h")
                    }
                }
                .padding(20)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // Subtly quiet custom foreground emphasis when another iPadOS window is active
            .opacity(appearsActive ? 1.0 : 0.85)
        }
        .preferredColorScheme(.dark)
        .navigationTitle(station.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Inspector", systemImage: "sidebar.right") {
                    showInspector.toggle()
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct BentoMetricCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // Calm semi-opaque surface with concentric geometry — never refractive Liquid Glass on data cards
        .background(.white.opacity(0.08), in: ConcentricRectangle())
    }
}

private struct StationInspectorPanel: View {
    let station: AdaptiveWorkspaceScene.Station

    var body: some View {
        Form {
            Section("Station Metadata") {
                LabeledContent("Location", value: station.name)
                LabeledContent("Current Level", value: station.tideHeight)
                LabeledContent("Next Extremum", value: station.status)
            }
        }
        .navigationTitle("Details")
    }
}
