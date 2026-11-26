import AppIntents
import FleetKit
import Intents
import IntentsUI
import SwiftUI
import UIKit

/// Siri tip + 1-tap natural "my car" phrase pinners + Shortcuts link card at the bottom of the Vehicle tab.
struct AppIntentDiscoveryCard: View {
    var vehicle: FleetVehicle? = nil
    @State private var isStatusTipVisible = true
    @State private var voiceShortcutsByType: [String: INVoiceShortcut] = [:]
    @State private var activeSheet: VoiceShortcutSheetItem?
    @State private var isShowingWidgetGallery = CommandLine.arguments.contains("--preview-siri-widgets")
    @State private var siriStatus = SiriCarCommandsSetup.authorizationStatus
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private let columns = [
        GridItem(.flexible(minimum: 130), spacing: 8),
        GridItem(.flexible(minimum: 130), spacing: 8)
    ]

    var body: some View {
        DashboardCard("Siri & Shortcuts", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ask Siri to check status, warm up your car, lock up, or review drives.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                carCommandsPermission

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(CarSiriVoicePhrase.allCases) { item in
                        phraseButton(for: item)
                    }
                }

                SiriTipView(intent: statusIntent, isVisible: $isStatusTipVisible)
                    .siriTipViewStyle(.automatic)

                Divider()

                Button {
                    isShowingWidgetGallery = true
                } label: {
                    DashboardCardLinkLabel(
                        title: "Preview Siri Cards",
                        systemImage: "rectangle.stack"
                    )
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                ShortcutsLink()
                    .shortcutsLinkStyle(.automatic)
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await reloadVoiceShortcuts()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { siriStatus = SiriCarCommandsSetup.authorizationStatus }
        }
        .sheet(isPresented: $isShowingWidgetGallery) {
            NavigationStack {
                SiriDynamicWidgetsPreviewSheet(preferredVIN: vehicle?.vin)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            VoiceShortcutSheetPresenter(item: sheet) {
                activeSheet = nil
                Task { await reloadVoiceShortcuts() }
            }
            .ignoresSafeArea()
        }
    }

    /// SiriKit Car Commands ("Lock my car", "Is my car locked?", "How much charge does my car
    /// have?") need Siri permission. They don't need the app name.
    @ViewBuilder
    private var carCommandsPermission: some View {
        switch siriStatus {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { siriStatus = await SiriCarCommandsSetup.requestAuthorization() }
                } label: {
                    Label("Allow Siri Car Commands", systemImage: "car.side.lock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Lets Siri lock, unlock, honk, and check your car's charge, and lets Maps plan EV routes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Siri car commands are off. Turn on Siri for Wattie in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.caption.weight(.semibold))
            }
        default:
            EmptyView()
        }
    }

    private func phraseButton(for item: CarSiriVoicePhrase) -> some View {
        let existing = voiceShortcutsByType[item.rawValue]
        let isAdded = existing != nil

        return Button {
            if let existing {
                activeSheet = .edit(existing)
            } else {
                activeSheet = .add(item.makeShortcut(for: vehicle), id: item.rawValue)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isAdded ? "checkmark" : item.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAdded ? AnyShapeStyle(AppTheme.chargeGreen) : AnyShapeStyle(.tint))
                    .frame(width: 18)

                Text("“\(existing?.invocationPhrase ?? item.phrase)”")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isAdded
                ? Text("Edit Siri phrase \(existing?.invocationPhrase ?? item.phrase)")
                : Text("Add Siri phrase \(item.phrase)")
        )
    }

    private var statusIntent: GetVehicleStatusIntent {
        let intent = GetVehicleStatusIntent()
        if let vehicle, !vehicle.vin.isEmpty {
            intent.vehicle = VehicleEntity(id: vehicle.vin, name: vehicle.name)
        }
        return intent
    }

    private func reloadVoiceShortcuts() async {
        let shortcuts: [INVoiceShortcut] = await withCheckedContinuation { continuation in
            INVoiceShortcutCenter.shared.getAllVoiceShortcuts { fetched, _ in
                continuation.resume(returning: fetched ?? [])
            }
        }
        var mapped: [String: INVoiceShortcut] = [:]
        for shortcut in shortcuts {
            if let activityType = shortcut.shortcut.userActivity?.activityType {
                mapped[activityType] = shortcut
            }
        }
        voiceShortcutsByType = mapped
    }
}

// MARK: - Live Siri Dynamic Widgets Gallery

private struct SiriDynamicWidgetsPreviewSheet: View {
    let preferredVIN: String?
    @Environment(\.dismiss) private var dismiss

    enum FilterSection: String, CaseIterable, Identifiable {
        case all
        case drives
        case vehicle
        case charging

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .drives: "Drives"
            case .vehicle: "Car & Climate"
            case .charging: "Charging"
            }
        }
    }

    @State private var selectedSection: FilterSection = .all
    @State private var vehicleName = "Midnight"
    @State private var vehicleEntity = VehicleEntity(id: FleetDemoVehicleState.demoVIN, name: "Midnight")
    @State private var drives: [DriveEntity] = []
    @State private var selectedDriveIndex = 0
    @State private var driveMapData: SiriRenderedMapData?
    @State private var statusEntity: VehicleStatusEntity?
    @State private var vehicleMapData: SiriRenderedMapData?
    @State private var charges: [ChargeSessionEntity] = []
    @State private var selectedChargeIndex = 0
    @State private var chargeMapData: SiriRenderedMapData?
    @State private var drivingStats: DrivingStatsEntity?
    @State private var previewService: FleetIntentService?
    @State private var driveMapRevision = 0
    @State private var chargeMapRevision = 0
    @State private var vehicleStatusRevision = 0
    @State private var vehicleMapRevision = 0
    @State private var vehicleMapStyle: SiriMapVisualStyle = .standard

    private struct VehiclePin: Equatable {
        let latitude: Double?
        let longitude: Double?
        let fallbackAddress: String?
        let style: SiriMapVisualStyle
        let revision: Int
    }

    private var vehiclePin: VehiclePin? {
        guard previewService != nil, let statusEntity else { return nil }
        return VehiclePin(latitude: statusEntity.latitude, longitude: statusEntity.longitude,
                          fallbackAddress: statusEntity.locationAddress, style: vehicleMapStyle,
                          revision: vehicleMapRevision)
    }

    private let previewDriveSessionKey = "preview-drives"
    private let previewChargeSessionKey = "preview-charges"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Widget Category", selection: $selectedSection) {
                    ForEach(FilterSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                if selectedSection == .all || selectedSection == .drives {
                    if !drives.isEmpty {
                        let safeIndex = min(max(selectedDriveIndex, 0), drives.count - 1)
                        siriPlatterCard(
                            prompt: "“Show my recent drives” or “How was my last drive?”",
                            subtitle: "Interactive Apple Maps route, start & end timeline, Autopilot segments, Satellite toggle & multi-drive stepper"
                        ) {
                            DriveSnippetView(
                                drive: drives[safeIndex],
                                allDrives: drives,
                                selectedIndex: safeIndex,
                                sessionKey: previewDriveSessionKey,
                                vehicleName: vehicleName,
                                mapData: driveMapData
                            )
                        }
                    }

                    if let drivingStats {
                        siriPlatterCard(
                            prompt: "“What are my driving stats this week?”",
                            subtitle: "Autopilot share progress bar & efficiency breakdown"
                        ) {
                            DrivingStatsSnippetView(stats: drivingStats)
                        }
                    }
                }

                if selectedSection == .all || selectedSection == .vehicle {
                    if let statusEntity {
                        siriPlatterCard(
                            prompt: "“How's my car?” or “Where is my car?”",
                            subtitle: "Battery & charge-limit gauge, Apple Maps parked-car pin, Directions link & live controls"
                        ) {
                            VehicleStatusSnippetView(status: statusEntity, mapData: vehicleMapData)
                        }

                        siriPlatterCard(
                            prompt: "“Warm up my car”",
                            subtitle: "Interactive cabin temperature +/- controls & active comfort badges"
                        ) {
                            ClimateControlSnippetView(
                                vehicle: vehicleEntity,
                                status: statusEntity,
                                appliedSummary: String(localized: "Climate on · warming cabin", comment: "Preview status subtitle for the Siri climate snippet card")
                            )
                        }
                    }
                }

                if selectedSection == .all || selectedSection == .charging {
                    if !charges.isEmpty {
                        let safeChargeIdx = min(max(selectedChargeIndex, 0), charges.count - 1)
                        siriPlatterCard(
                            prompt: "“How much did my last charge cost?”",
                            subtitle: "Apple Maps charger pin, battery-added fill bar & session stepper"
                        ) {
                            ChargeSessionSnippetView(
                                session: charges[safeChargeIdx],
                                allSessions: charges,
                                selectedIndex: safeChargeIdx,
                                sessionKey: previewChargeSessionKey,
                                vehicleName: vehicleName,
                                mapData: chargeMapData
                            )
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppScreenBackground())
        .navigationTitle("Siri Dynamic Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            previewService = nil
            SiriSnippetStateStore.shared.setSelectedDriveIndex(0, for: previewDriveSessionKey)
            SiriSnippetStateStore.shared.setSelectedDriveIndex(0, for: previewChargeSessionKey)
            await loadWidgetData()
        }
        .onReceive(NotificationCenter.default.publisher(for: SiriSnippetStateStore.stateDidChangeNotification)) { notification in
            guard previewService != nil else { return }
            switch SiriSnippetStateStore.Change(notification: notification) {
            case .selection(let key):
                if key == previewDriveSessionKey { driveMapRevision += 1 }
                if key == previewChargeSessionKey { chargeMapRevision += 1 }
            case .mapStyle("drive"):
                driveMapRevision += 1
            case .mapStyle("charge"):
                chargeMapRevision += 1
            case .mapStyle("vehicle"):
                vehicleMapStyle = SiriSnippetStateStore.shared.mapStyle(for: "vehicle")
            case .vehicleStatus(let vin):
                if vin == vehicleEntity.id { vehicleStatusRevision += 1 }
            case .all, .mapStyle:
                refreshGalleryMaps()
                vehicleMapRevision += 1
                vehicleStatusRevision += 1
            }
        }
        .task(id: driveMapRevision) {
            guard let previewService, !drives.isEmpty else { return }
            let store = SiriSnippetStateStore.shared
            let index = store.selectedDriveIndex(for: previewDriveSessionKey, count: drives.count)
            if selectedDriveIndex != index {
                driveMapData = nil
                selectedDriveIndex = index
            }
            let map = await SiriMapSnapshotRenderer.renderDriveRoute(
                for: drives[index], service: previewService, style: store.mapStyle(for: "drive")
            )
            if !Task.isCancelled { driveMapData = map }
        }
        .task(id: chargeMapRevision) {
            guard previewService != nil, !charges.isEmpty else { return }
            let store = SiriSnippetStateStore.shared
            let index = store.selectedDriveIndex(for: previewChargeSessionKey, count: charges.count)
            if selectedChargeIndex != index {
                chargeMapData = nil
                selectedChargeIndex = index
            }
            let charge = charges[index]
            let map = await SiriMapSnapshotRenderer.renderLocationPin(
                latitude: charge.latitude, longitude: charge.longitude, fallbackPlaceQuery: charge.location,
                style: store.mapStyle(for: "charge"), accentHex: charge.isSupercharger ? 0xFF3B30 : 0x30D158
            )
            if !Task.isCancelled { chargeMapData = map }
        }
        .task(id: vehicleStatusRevision) {
            guard vehicleStatusRevision > 0, let previewService,
                  let snapshot = try? await previewService.snapshot(vin: vehicleEntity.id),
                  !Task.isCancelled else { return }
            statusEntity = VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicleName,
                                               locationAddress: statusEntity?.locationAddress ?? "Apple Park Way, Cupertino")
        }
        .task(id: vehiclePin) { [vehiclePin] in
            guard let vehiclePin else { return }
            let map = await SiriMapSnapshotRenderer.renderLocationPin(
                latitude: vehiclePin.latitude, longitude: vehiclePin.longitude,
                fallbackPlaceQuery: vehiclePin.fallbackAddress, style: vehiclePin.style
            )
            if !Task.isCancelled { vehicleMapData = map }
        }
    }

    private func siriPlatterCard<Content: View>(
        prompt: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                Text(prompt)
                    .font(.subheadline.weight(.semibold))
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }

    private func resolvedPreviewService() -> FleetIntentService {
        let liveService = FleetIntentService.make()
        if FleetSandboxStore.shared.mode() == .demoVehicle || FleetSharedTokenStore.shared.accessToken() != nil {
            return liveService
        }
        let fallbackSandbox = FleetSandboxStore(appGroup: "TeslaSiri.WidgetPreviewFallback")
        fallbackSandbox.setMode(.demoVehicle)
        return FleetIntentService(sandbox: fallbackSandbox)
    }

    private func loadWidgetData() async {
        let service = resolvedPreviewService()
        do {
            let resolved = try await service.resolvedVehicle(preferredVIN)
            vehicleName = resolved.name
            vehicleEntity = VehicleEntity(id: resolved.vin, name: resolved.name)

            async let driveRead = service.drives(vin: resolved.vin, limit: 5)
            async let statusRead = service.snapshot(vin: resolved.vin)
            async let chargeRead = service.charges(vin: resolved.vin, limit: 5)
            let (rawDrives, snapshot, rawCharges) = try await (driveRead, statusRead, chargeRead)
            guard !Task.isCancelled else { return }
            drives = rawDrives.map(DriveEntity.init(info:))
            drivingStats = DrivingStatsEntity(vehicle: resolved, period: .last7Days, drives: rawDrives)

            statusEntity = VehicleStatusEntity(
                snapshot: snapshot,
                vehicleName: resolved.name,
                locationAddress: "Apple Park Way, Cupertino"
            )

            charges = rawCharges.map(ChargeSessionEntity.init(info:))
            previewService = service
            refreshGalleryMaps()
        } catch {
            guard !Task.isCancelled else { return }
            let demoSandbox = FleetSandboxStore(appGroup: "TeslaSiri.WidgetPreviewDemo")
            demoSandbox.setMode(.demoVehicle)
            let demoService = FleetIntentService(sandbox: demoSandbox)
            if let resolved = try? await demoService.resolvedVehicle(nil) {
                vehicleName = resolved.name
                vehicleEntity = VehicleEntity(id: resolved.vin, name: resolved.name)
                let rawDrives = (try? await demoService.drives(vin: resolved.vin, limit: 5)) ?? []
                drives = rawDrives.map(DriveEntity.init(info:))
                drivingStats = DrivingStatsEntity(vehicle: resolved, period: .last7Days, drives: rawDrives)
                if let snap = try? await demoService.snapshot(vin: resolved.vin) {
                    statusEntity = VehicleStatusEntity(
                        snapshot: snap,
                        vehicleName: resolved.name,
                        locationAddress: "Apple Park Way, Cupertino"
                    )
                }
                let rawCharges = (try? await demoService.charges(vin: resolved.vin, limit: 5)) ?? []
                charges = rawCharges.map(ChargeSessionEntity.init(info:))
                guard !Task.isCancelled else { return }
                previewService = demoService
                refreshGalleryMaps()
            }
        }
    }

    private func refreshGalleryMaps() {
        driveMapRevision += 1
        chargeMapRevision += 1
        vehicleMapStyle = SiriSnippetStateStore.shared.mapStyle(for: "vehicle")
    }
}

private enum VoiceShortcutSheetItem: Identifiable {
    case add(INShortcut, id: String)
    case edit(INVoiceShortcut)

    var id: String {
        switch self {
        case .add(_, let id): "add-\(id)"
        case .edit(let voiceShortcut): "edit-\(voiceShortcut.identifier.uuidString)"
        }
    }
}

private struct VoiceShortcutSheetPresenter: UIViewControllerRepresentable {
    let item: VoiceShortcutSheetItem
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        switch item {
        case .add(let shortcut, _):
            let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
            controller.delegate = context.coordinator
            return controller
        case .edit(let voiceShortcut):
            let controller = INUIEditVoiceShortcutViewController(voiceShortcut: voiceShortcut)
            controller.delegate = context.coordinator
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: (any Error)?) {
            onDismiss()
        }

        func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
            onDismiss()
        }

        func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: (any Error)?) {
            onDismiss()
        }

        func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID) {
            onDismiss()
        }

        func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
            onDismiss()
        }
    }
}

