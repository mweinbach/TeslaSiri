import FleetKit
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    private enum GallerySize: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }

        var title: String {
            switch self {
            case .small:
                String(localized: "Small", comment: "Widget gallery size picker choice for small widgets.")
            case .medium:
                String(localized: "Medium", comment: "Widget gallery size picker choice for medium widgets.")
            case .large:
                String(localized: "Large", comment: "Widget gallery size picker choice for large widgets.")
            }
        }
    }

    private enum FeedbackPreviewMode: String, CaseIterable, Identifiable {
        case live, confirmed, waking, failed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live:
                String(localized: "Resting", comment: "Widget gallery activation state choice showing no confirmation.")
            case .confirmed:
                String(localized: "Confirmed", comment: "Widget gallery activation state choice showing a successful action.")
            case .waking:
                String(localized: "Waking", comment: "Widget gallery activation state choice showing a sleeping-car wait.")
            case .failed:
                String(localized: "Error", comment: "Widget gallery activation state choice showing a failed action.")
            }
        }
    }

    @State private var snapshot: FleetWidgetSnapshot?
    @State private var isLoading = false
    @State private var isUsingSample = false
    @State private var selectedSize: GallerySize = .small
    @State private var feedbackPreviewMode: FeedbackPreviewMode = .live
    @State private var sample: FleetWidgetSnapshot = {
        var value = FleetWidgetSnapshot.sample
        if value.openClosures == nil {
            value.openClosures = []
        }
        return value
    }()

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

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Widget size", selection: $selectedSize) {
                        ForEach(GallerySize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Text("Activation state")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Picker("Activation state", selection: $feedbackPreviewMode) {
                            ForEach(FeedbackPreviewMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption.weight(.semibold))
                    }
                }

                switch selectedSize {
                case .small:
                    LazyVGrid(columns: smallColumns, spacing: 14) {
                        ForEach(VehicleWidgetTopic.allCases) { topic in
                            previewCard(for: topic, family: .systemSmall)
                        }
                    }
                case .medium:
                    VStack(spacing: 14) {
                        ForEach(VehicleWidgetTopic.allCases) { topic in
                            previewCard(for: topic, family: .systemMedium)
                        }
                    }
                case .large:
                    previewCard(for: .overview, family: .systemLarge)
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
                    StatusBadge(snapshot.name, systemImage: "car.fill", tint: AppTheme.accent)
                } else if isUsingSample {
                    StatusBadge("Sample", systemImage: "sparkles", tint: .secondary)
                }
            }

            Text("Add live status and quick controls to your Home Screen, Lock Screen, Control Center, or Apple HomeView. Buttons confirm activation inline right on the widget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewSnapshot(for topic: VehicleWidgetTopic) -> FleetWidgetSnapshot {
        var value = snapshot ?? sample
        switch feedbackPreviewMode {
        case .live:
            return value
        case .confirmed:
            let action: FleetWidgetAction = switch topic {
            case .overview, .security: .lock
            case .charging: .startCharging
            case .climate: .startClimate
            }
            if topic == .climate { value.climateOn = true }
            if topic == .charging {
                value.chargingState = "Charging"
                value.chargerPowerKW = value.chargerPowerKW ?? 11.5
            }
            value.actionFeedback = .confirmed(action: action)
            return value
        case .waking:
            let action: FleetWidgetAction = switch topic {
            case .overview, .climate: .startClimate
            case .charging: .startCharging
            case .security: .lock
            }
            if topic == .overview || topic == .climate {
                value.climateOn = false
                value.climateStartRequestedAt = .now
            } else if topic == .charging {
                value.chargingState = "Stopped"
            }
            value.actionFeedback = .waking(action: action)
            return value
        case .failed:
            let action: FleetWidgetAction = switch topic {
            case .overview, .security: .lock
            case .charging: .startCharging
            case .climate: .startClimate
            }
            if topic == .charging {
                value.chargingState = "Stopped"
            }
            let msg: String = switch topic {
            case .charging: "Plug in to charge"
            case .climate: "Car is asleep"
            case .overview, .security: "Car timed out"
            }
            value.actionFeedback = FleetWidgetActionFeedback(action: action, outcome: .failed, message: msg)
            return value
        }
    }

    private func previewCard(for topic: VehicleWidgetTopic, family: WidgetFamily) -> some View {
        let displayed = previewSnapshot(for: topic)
        let cardHeight: CGFloat = switch family {
        case .systemSmall: 168
        case .systemMedium: 164
        default: 356
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(topic.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VehicleWidgetPanel(
                snapshot: displayed,
                topic: topic,
                family: family
            )
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .background(VehicleWidgetBackdrop(snapshot: displayed, topic: topic))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AppTheme.topEdgeHighlight, AppTheme.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: AppTheme.surfaceShadow, radius: 12, y: 4)
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
                    tint: AppTheme.accent,
                    text: "Touch and hold your Home Screen, tap Edit, then Add Widget and search for Wattie. Each widget follows your selected car or pins to a specific vehicle."
                )
                Divider()
                instructionRow(
                    "Interactive Confirmation",
                    symbol: "checkmark.circle.fill",
                    tint: AppTheme.chargeGreen,
                    text: "Tapping Lock, Climate, Charge, or Refresh highlights the control immediately and displays an inline confirmation or retry message when the car responds."
                )
                Divider()
                instructionRow(
                    "Apple HomeView",
                    symbol: "house",
                    tint: AppTheme.alertAmber,
                    text: "Pick Wattie’s small widgets from your connected iPhone in HomeView to keep charging, climate, and security visible together."
                )
                Divider()
                instructionRow(
                    "Control Center & Action Button",
                    symbol: "switch.2",
                    tint: AppTheme.climateBlue,
                    text: "Add Lock Car, Start Car Climate, or Start Car Charging in Control Center, Lock Screen controls, or the Action button with live status confirmation."
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

    private func instructionRow(_ title: LocalizedStringKey, symbol: String, tint: Color, text: LocalizedStringKey) -> some View {
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

#if DEBUG
#Preview("Widget Gallery") {
    NavigationStack {
        WidgetGalleryView()
    }
}
#endif
