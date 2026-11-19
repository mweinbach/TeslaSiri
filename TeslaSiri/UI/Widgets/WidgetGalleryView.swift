import FleetKit
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    @State private var snapshot: FleetWidgetSnapshot?
    @State private var isLoading = false
    @State private var isUsingSample = false
    @State private var showsMedium = false
    @State private var sample = FleetWidgetSnapshot.sample

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var smallColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Picker("Widget size", selection: $showsMedium) {
                    Text("Small").tag(false)
                    Text("Medium").tag(true)
                }
                .pickerStyle(.segmented)

                if showsMedium {
                    VStack(spacing: 14) {
                        ForEach(VehicleWidgetTopic.allCases) { topic in
                            previewCard(for: topic, family: .systemMedium)
                        }
                    }
                } else {
                    LazyVGrid(columns: smallColumns, spacing: 14) {
                        ForEach(VehicleWidgetTopic.allCases) { topic in
                            previewCard(for: topic, family: .systemSmall)
                        }
                    }
                }

                setupInstructions
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentWidth()
        }
        .background(AppScreenBackground())
        .navigationTitle("Widgets & Controls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh Widgets", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text("Your car, at a glance")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                if let snapshot, !isUsingSample {
                    StatusBadge(snapshot.name, systemImage: "car.fill", tint: .blue)
                } else if isUsingSample {
                    StatusBadge("Sample", systemImage: "sparkles", tint: .secondary)
                }
            }

            Text("Add live status and quick controls to your Home Screen, Lock Screen, Control Center, or Apple HomeView.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewCard(for topic: VehicleWidgetTopic, family: WidgetFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VehicleWidgetPanel(
                snapshot: snapshot ?? sample,
                topic: topic,
                family: family
            )
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: family == .systemSmall ? 168 : 164)
            .appSurface(cornerRadius: 24)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(topic.title) widget preview")
        }
    }

    private var setupInstructions: some View {
        DashboardCard("How to Add", systemImage: "plus.square.on.square") {
            VStack(alignment: .leading, spacing: 14) {
                instructionRow(
                    "Home & Lock Screen",
                    symbol: "square.grid.2x2",
                    tint: .blue,
                    text: "Touch and hold your Home Screen, tap Edit, then Add Widget and search for Wattie. Each widget follows your selected car or pins to a specific vehicle."
                )
                Divider()
                instructionRow(
                    "Apple HomeView",
                    symbol: "house",
                    tint: .orange,
                    text: "Pick Wattie’s small widgets from your connected iPhone in HomeView to keep charging, climate, and security visible together."
                )
                Divider()
                instructionRow(
                    "Control Center & Action Button",
                    symbol: "switch.2",
                    tint: .green,
                    text: "Add Lock Car, Start Car Climate, or Start Car Charging in Control Center, Lock Screen controls, or the Action button."
                )
                Divider()
                instructionRow(
                    "Refresh Schedule",
                    symbol: "arrow.clockwise",
                    tint: .secondary,
                    text: "Widgets refresh on iOS’s background schedule (every 15 min while charging, 30 min otherwise) and whenever you refresh inside Wattie or tap the widget’s refresh button."
                )
            }
        }
    }

    private func instructionRow(_ title: String, symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await FleetWidgetStore.shared.load(vin: nil)
            isUsingSample = false
            FleetWidgetStore.reload()
        } catch {
            snapshot = nil
            isUsingSample = true
        }
    }
}
