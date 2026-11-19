import AppIntents
import FleetKit
import SwiftUI

struct DrivesView: View {
    let store: FleetDataStore
    var requestedSessionID: String? = nil
    var onReload: (() async -> Void)? = nil

    @State private var endpointAddresses: [String: DriveEndpointAddresses] = [:]
    @State private var selectedPointIndex = 0
    @State private var selectedSessionID: String?
    @State private var selectedPlaceID: String?
    @State private var searchText = ""
    @State private var placeToRename: DrivePlace?
    @State private var nicknameDraft = ""
    @State private var nicknameSaveError: String?

    private var placesIndex: DrivePlacesIndex? {
        store.selectedVehicle.map { DrivePlacesIndex.shared(vin: $0.vin, provider: store.provider) }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentDrives: [FleetDriveSession] {
        let recent = store.selectedVehicleRecentDrives
        var visible = Array(recent.prefix(10))
        if let targetID = selectedSessionID ?? requestedSessionID,
           !targetID.isEmpty,
           !visible.contains(where: { $0.sessionID == targetID }),
           let matching = recent.first(where: { $0.sessionID == targetID }) {
            visible.append(matching)
        }
        return visible
    }

    var body: some View {
        let index = placesIndex
        let query = trimmedSearch
        let place = selectedPlaceID.flatMap { index?.place(id: $0) }
        let results = query.isEmpty ? nil : index?.search(query, at: place)
        let visiblePlaces = results?.places ?? index?.frequentPlaces ?? []
        let visibleDrives = results?.drives ?? place.flatMap { index?.drives(at: $0) } ?? recentDrives
        let title = place.map { "Drives to and from \($0.displayName)" } ?? (query.isEmpty ? "Recent drives" : "Matching drives")
        let targetID = selectedSessionID ?? requestedSessionID
        let selected = visibleDrives.first { $0.sessionID == targetID } ?? visibleDrives.first
        let selection = selectedSessionBinding(fallback: visibleDrives.first?.sessionID)
        let lookups = endpointLookups(for: visibleDrives)
        let labels = labeledEndpointAddresses(for: visibleDrives)

        DrivesPostureContainer(
            store: store,
            drives: visibleDrives,
            drivesTitle: title,
            places: visiblePlaces,
            isIndexingPlaces: index?.isIndexing ?? false,
            selectedPlaceID: $selectedPlaceID,
            onEditNickname: { place in
                nicknameDraft = place.nickname ?? ""
                placeToRename = place
            },
            selectedDrive: selected,
            endpointAddresses: labels,
            selectedSessionID: selection,
            selectedPointIndex: $selectedPointIndex,
            resolvedRoute: resolvedRoute(for:),
            onReload: reloadDrives
        )
        .observeDuoPosture()
        .environment(\.vehicleModelSpec, selectedVehicleModelSpec)
        .background(AppScreenBackground())
        .navigationTitle("Drives")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            drivesToolbarContent(for: visibleDrives, labels: labels, selectedID: selected?.sessionID, selection: selection)
        }
        .alert("Edit Nickname", item: $placeToRename) { place in
            TextField("Nickname", text: $nicknameDraft)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let nickname = nicknameDraft
                Task {
                    do {
                        try await index?.setNickname(nickname, for: place.id)
                    } catch {
                        nicknameSaveError = error.localizedDescription
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: { place in
            Text("Leave the nickname blank to use “\(place.name)”.")
        }
        .alert("Couldn’t Save Nickname", item: $nicknameSaveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onChange(of: store.selectedVehicle?.vin) {
            placeToRename = nil
        }
        .onChange(of: requestedSessionID, initial: true) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            selectedSessionID = newValue
            selectedPointIndex = 0
        }
        .task(id: lookups) {
            await refreshEndpointAddresses(for: lookups)
        }
        .task(id: store.selectedVehicle?.vin) {
            await placesIndex?.refresh(using: store)
        }
        .searchable(text: $searchText, prompt: "Search places and addresses")
        .onChange(of: searchText) {
            if !trimmedSearch.isEmpty { selectedPlaceID = nil }
        }
        .onChange(of: visibleDrives.map(\.sessionID)) { _, ids in
            if let current = selectedSessionID, !ids.contains(current) {
                selectedSessionID = ids.first
                selectedPointIndex = 0
            }
        }
        .appEntityIdentifier(selected.flatMap(driveEntityIdentifier(for:)))
    }

    /// Endpoint labels with place names ("Equinox") in place of street addresses where the
    /// places index knows them.
    private func labeledEndpointAddresses(for drives: [FleetDriveSession]) -> [String: DriveEndpointAddresses] {
        guard let placesIndex else { return endpointAddresses }
        var labeled = endpointAddresses
        for drive in drives {
            var addresses = DriveEndpointAddresses(
                start: drive.startAddress ?? endpointAddresses[drive.sessionID]?.start,
                end: drive.endAddress ?? endpointAddresses[drive.sessionID]?.end
            )
            if let name = placesIndex.origin(of: drive)?.endpointName { addresses.start = name }
            if let name = placesIndex.destination(of: drive)?.endpointName { addresses.end = name }
            labeled[drive.sessionID] = addresses
        }
        return labeled
    }

    @ToolbarContentBuilder
    private func drivesToolbarContent(
        for drives: [FleetDriveSession],
        labels: [String: DriveEndpointAddresses],
        selectedID: String?,
        selection: Binding<String>
    ) -> some ToolbarContent {
        if drives.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(drives) { drive in
                        Button {
                            selection.wrappedValue = drive.sessionID
                        } label: {
                            let label = toolbarSessionTitle(for: drive, addresses: labels[drive.sessionID])
                            if drive.sessionID == selectedID {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                } label: {
                    Label("Select Drive", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
            }
        }

        if #available(iOS 27.3, macOS 27.3, visionOS 27.3, *) {
            ToolbarItem(placement: .topBarTrailing) {
                refreshToolbarButton
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                refreshToolbarButton
            }
        }
    }

    private var refreshToolbarButton: some View {
        Button {
            Task { await reloadDrives() }
        } label: {
            if store.isLoadingDrives || store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh Drives", systemImage: "arrow.clockwise")
            }
        }
        .disabled(store.isLoadingDrives || store.isRefreshing)
    }

    private func toolbarSessionTitle(for drive: FleetDriveSession, addresses: DriveEndpointAddresses?) -> String {
        let date = drive.startedAtDate.formatted(date: .abbreviated, time: .shortened)
        let summary = driveEndpointSummary(drive, endpointAddresses: addresses)
        return "\(date) · \(summary)"
    }

    private func reloadDrives() async {
        if let onReload {
            await onReload()
        } else {
            await store.refresh()
        }
        await placesIndex?.refresh(using: store)
    }

    private func selectedSessionBinding(fallback: String?) -> Binding<String> {
        Binding {
            selectedSessionID ?? requestedSessionID ?? fallback ?? ""
        } set: { newValue in
            selectedSessionID = newValue
            selectedPointIndex = 0
        }
    }

    private var selectedVehicleModelSpec: VehicleModelSpec {
        guard let vehicle = store.selectedVehicle else { return .showroomDefault }
        return VehicleModelSpec(configuration: vehicle.latest?.vehicleConfiguration, vin: vehicle.vin)
    }

    private func driveEntityIdentifier(for drive: FleetDriveSession) -> EntityIdentifier? {
        guard !drive.sessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID)
    }

    private nonisolated struct EndpointLookup: Equatable {
        let drive: FleetDriveSession
        let endpoints: [FleetRoutePoint]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.drive.sessionID == rhs.drive.sessionID
                && lhs.drive.startAddress == rhs.drive.startAddress
                && lhs.drive.endAddress == rhs.drive.endAddress
                && lhs.endpoints == rhs.endpoints
        }
    }

    private func endpointLookups(for drives: [FleetDriveSession]) -> [EndpointLookup] {
        drives.compactMap { drive in
            guard drive.startAddress == nil || drive.endAddress == nil else { return nil }
            let route = resolvedRoute(for: drive)
            let endpoints = [route.first, route.last].compactMap { point in
                point.map { FleetRoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
            }
            return EndpointLookup(drive: drive, endpoints: endpoints)
        }
    }

    private func resolvedRoute(for drive: FleetDriveSession) -> [FleetRoutePoint] {
        let cachedRoute = store.route(for: drive)
        return cachedRoute.isEmpty ? drive.route : cachedRoute
    }

    private func refreshEndpointAddresses(for lookups: [EndpointLookup]) async {
        guard !Task.isCancelled else { return }
        let ids = Set(lookups.map { $0.drive.sessionID })
        let retained = endpointAddresses.filter { ids.contains($0.key) }
        if retained.count != endpointAddresses.count { endpointAddresses = retained }

        for lookup in lookups {
            guard !Task.isCancelled else { return }
            let addresses = await driveEndpointAddressGeocoder.addresses(for: lookup.drive, route: lookup.endpoints)
            guard !Task.isCancelled else { return }
            let missing = DriveEndpointAddresses(
                start: lookup.drive.startAddress == nil ? addresses.start : nil,
                end: lookup.drive.endAddress == nil ? addresses.end : nil
            )
            let resolved = missing.start != nil || missing.end != nil ? missing : nil
            if endpointAddresses[lookup.drive.sessionID] != resolved {
                endpointAddresses[lookup.drive.sessionID] = resolved
            }
        }
    }
}

private struct DrivesPostureContainer: View {
    let store: FleetDataStore
    let drives: [FleetDriveSession]
    let drivesTitle: String
    let places: [DrivePlace]
    let isIndexingPlaces: Bool
    @Binding var selectedPlaceID: String?
    let onEditNickname: (DrivePlace) -> Void
    let selectedDrive: FleetDriveSession?
    let endpointAddresses: [String: DriveEndpointAddresses]
    @Binding var selectedSessionID: String
    @Binding var selectedPointIndex: Int
    let resolvedRoute: (FleetDriveSession) -> [FleetRoutePoint]
    let onReload: () async -> Void

    @Environment(\.duoPosture) private var duoPosture

    var body: some View {
        if drives.isEmpty {
            ScrollView {
                VStack(spacing: 20) {
                    if selectedPlaceID != nil || !places.isEmpty {
                        placesStrip
                    }
                    if store.isLoadingDrives {
                        LoadingCard(title: "Drives", message: "Loading drives…")
                    } else {
                        CardContainer(title: "Drives", systemImage: "map.fill") {
                            ContentUnavailableView(
                                drivesTitle == "Recent drives" ? "No drives" : "No matching drives",
                                systemImage: "map",
                                description: Text(drivesTitle == "Recent drives"
                                    ? "Recent drive sessions were not returned for this vehicle."
                                    : "Try another place or search.")
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .duoSingleCardStage()
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await onReload()
            }
        } else if duoPosture.prefersSplitArrangement, let selectedDrive {
            let route = resolvedRoute(selectedDrive)

            DuoSplitWorkspace(primaryRatio: 0.52) {
                DriveMapCard(
                    drive: selectedDrive,
                    route: route,
                    fillsPane: true,
                    compactHeight: duoPosture.compactMapHeight,
                    selectedPointIndex: $selectedPointIndex,
                    onLoadRoute: {
                        await store.refreshRoute(for: selectedDrive)
                    }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } secondary: {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        placesStrip

                        DriveSessionPicker(
                            drives: drives,
                            endpointAddresses: endpointAddresses,
                            selectedSessionID: $selectedSessionID,
                            title: drivesTitle
                        )

                        DrivePlaybackSection(
                            drive: selectedDrive,
                            route: route,
                            selectedPointIndex: $selectedPointIndex,
                            onLoadRoute: {
                                await store.refreshRoute(for: selectedDrive)
                            }
                        )

                        DriveSessionSummary(
                            drive: selectedDrive,
                            endpointAddresses: endpointAddresses[selectedDrive.sessionID],
                            hasRoute: !route.isEmpty
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: AppTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await onReload()
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    placesStrip

                    DriveSessionPicker(
                        drives: drives,
                        endpointAddresses: endpointAddresses,
                        selectedSessionID: $selectedSessionID,
                        title: drivesTitle
                    )

                    if let selectedDrive {
                        let route = resolvedRoute(selectedDrive)

                        DriveMapCard(
                            drive: selectedDrive,
                            route: route,
                            fillsPane: false,
                            compactHeight: duoPosture.compactMapHeight,
                            selectedPointIndex: $selectedPointIndex,
                            onLoadRoute: {
                                await store.refreshRoute(for: selectedDrive)
                            }
                        )

                        DrivePlaybackSection(
                            drive: selectedDrive,
                            route: route,
                            selectedPointIndex: $selectedPointIndex,
                            onLoadRoute: {
                                await store.refreshRoute(for: selectedDrive)
                            }
                        )

                        DriveSessionSummary(
                            drive: selectedDrive,
                            endpointAddresses: endpointAddresses[selectedDrive.sessionID],
                            hasRoute: !route.isEmpty
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
                .readableContentWidth()
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await onReload()
            }
        }
    }
}

extension DrivesPostureContainer {
    var placesStrip: some View {
        DrivePlacesStrip(
            places: places,
            isIndexing: isIndexingPlaces,
            selectedPlaceID: $selectedPlaceID,
            onEditNickname: onEditNickname
        )
    }
}

private struct DrivePlaybackSection: View {
    let drive: FleetDriveSession
    let route: [FleetRoutePoint]
    @Binding var selectedPointIndex: Int
    let onLoadRoute: () async -> Void

    private var entityIdentifier: EntityIdentifier? {
        guard !drive.sessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID)
    }

    var body: some View {
        if route.isEmpty {
            Button {
                Task { await onLoadRoute() }
            } label: {
                Label("Load Route", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .appEntityIdentifier(entityIdentifier)
        } else {
            CardContainer(title: "Route playback", systemImage: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 16) {
                    DriveReplayStage(
                        route: route,
                        selectedPointIndex: $selectedPointIndex,
                        driveSessionID: drive.sessionID
                    )

                    DriveRoutePositionScrubber(
                        sampleCount: route.count,
                        selectedSampleIndex: $selectedPointIndex,
                        driveSessionID: drive.sessionID
                    )

                    if let selectedPoint = route[safe: selectedPointIndex] {
                        DriveRoutePositionSummary(
                            point: selectedPoint,
                            index: selectedPointIndex,
                            count: route.count,
                            driveSessionID: drive.sessionID
                        )
                    }
                }
            }
            .appEntityIdentifier(entityIdentifier)
        }
    }
}

private struct DriveMapCard: View {
    let drive: FleetDriveSession
    let route: [FleetRoutePoint]
    let fillsPane: Bool
    let compactHeight: CGFloat
    @Binding var selectedPointIndex: Int
    let onLoadRoute: () async -> Void

    var body: some View {
        DriveRouteMap(
            route: route,
            selectedPointIndex: selectedPointIndex,
            driveSessionID: drive.sessionID
        )
        .frame(
            minHeight: fillsPane ? 220 : compactHeight,
            maxHeight: fillsPane ? .infinity : compactHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if !route.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.tint)
                    Text(routeBadgeText)
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.75)
                }
                .padding(10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 0.75)
        }
        .shadow(color: AppTheme.surfaceShadow, radius: 10, y: 3)
        .task(id: drive.sessionID) {
            selectedPointIndex = 0
            if route.isEmpty {
                await onLoadRoute()
            }
        }
    }

    private var routeBadgeText: String {
        let distance = formattedNumber(drive.distanceMiles, fractionLength: 1, suffix: " mi")
        if let durationMS = drive.durationMS, durationMS > 0 {
            return "\(distance) · \(formattedDuration(milliseconds: durationMS))"
        }
        return "\(distance) route"
    }
}
