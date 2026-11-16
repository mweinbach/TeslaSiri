import FleetKit
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    @State private var snapshot: FleetWidgetSnapshot?
    @State private var message: String?
    @State private var showsMedium = false
    @State private var sample = FleetWidgetSnapshot.sample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your car, at a glance").font(.title2.weight(.semibold))
                Text("Keep vehicle status and quick actions on your iPhone Home Screen or Apple HomeView.")
                    .foregroundStyle(.secondary)
                Picker("Widget size", selection: $showsMedium) {
                    Text("Small · HomeView").tag(false)
                    Text("Medium · iPhone").tag(true)
                }
                .pickerStyle(.segmented)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(VehicleWidgetTopic.allCases) { topic in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(topic.title).font(.headline)
                        VehicleWidgetPanel(snapshot: snapshot ?? sample, topic: topic, family: showsMedium ? .systemMedium : .systemSmall)
                            .padding(16)
                            .frame(width: showsMedium ? nil : 170, height: 180)
                            .frame(maxWidth: showsMedium ? .infinity : nil)
                            .appSurface(cornerRadius: 24)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(topic.title) widget preview")
                    }
                }
                setupInstructions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentWidth()
        }
        .background(AppScreenBackground())
        .navigationTitle("Widgets & Controls")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            instruction("iPhone & iPad", symbol: "square.grid.2x2", text: "Touch and hold the Home Screen, tap Edit, then Add Widget. Search for Wattie. Each widget can follow your selected car or stay pinned to a vehicle. Vehicle also offers a large layout; smaller status widgets fit the Lock Screen.")
            instruction("Apple HomeView", symbol: "square.grid.2x2", text: "Choose Wattie’s small widgets from your connected iPhone in HomeView’s widget picker. Add several to keep charging, climate, and security visible together. Widgets offer quick actions; they don’t add your Tesla as an accessory in Apple’s Home app.")
            instruction("Control Center", symbol: "power", text: "Touch and hold Control Center, tap Add a Control, and search for Wattie. Add Lock Car, Start Car Climate, or Start Car Charging. These use the car currently selected in Wattie and can also be assigned to the Lock Screen or Action button.")
            instruction("Updates", symbol: "arrow.clockwise", text: "Widgets fetch data from your selected provider on the system’s refresh schedule. Tap the refresh symbol to request new data. Times shown belong to the vehicle data, which may be older than the latest fetch. Updates aren’t continuous or instant. Quick actions lock, start climate, or start charging; use the app for commands that need confirmation.")
        }
        .padding(18)
        .appSurface(cornerRadius: 22)
    }

    private func instruction(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refresh() async {
        do {
            snapshot = try await FleetWidgetStore.shared.load(vin: nil)
            message = "Previews for \(snapshot?.name ?? "your car"). Add widgets using the instructions below."
        } catch {
            snapshot = nil
            message = "Sample previews. Sign in or enable Demo Car in Diagnostics to see your vehicle’s data."
        }
    }
}
