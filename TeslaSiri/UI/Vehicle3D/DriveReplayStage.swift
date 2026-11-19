import CoreLocation
import SwiftUI

extension EnvironmentValues {
    /// The 3D build for the selected vehicle, for views that only receive drive data.
    @Entry var vehicleModelSpec: VehicleModelSpec = .showroomDefault
}

/// Replays a recorded drive in 3D, on the real road. The drive is snapped to Apple Maps roads
/// (`DriveRoadPath`), and playback moves continuously along that road at 1x, 5x or 20x: lane
/// lines stream with the car's motion and bend with the road ahead, and the blue planned path shows
/// only where Tessie recorded Autopilot or FSD steering. Below the 3D view, Look Around stills
/// follow the car and crossfade as it moves; tapping one opens the interactive viewer. The scrubber and map follow the playhead and scrubbing
/// moves it.
struct DriveReplayStage: View {
    let route: [FleetRoutePoint]
    @Binding var selectedPointIndex: Int
    var driveSessionID: String?

    @Environment(\.vehicleModelSpec) private var spec
    @Environment(\.scenePhase) private var scenePhase
    @State private var replay = DriveReplayController()
    @AppStorage("drivesReplayShows3D") private var shows3D = true
    @AppStorage("drivesReplayShowsStreetView") private var showsStreetView = true

    private var state: VehicleStageState {
        guard !route.isEmpty else { return VehicleStageState() }
        return VehicleStageState(drivePoint: min(max(selectedPointIndex, 0), route.count - 1), in: route)
    }

    private var usesTimer: Bool {
        replay.isPlaying && !shows3D && scenePhase == .active
    }

    private var routeToLoad: DriveReplayController.Route? {
        guard shows3D || showsStreetView || replay.isPlaying else { return nil }
        return DriveReplayController.Route(driveSessionID: driveSessionID, points: route)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            viewOptions

            if shows3D {
                stage
                matchStatus
            } else if showsStreetView {
                compactControls
            }

            if showsStreetView {
                DriveStreetView(coordinate: streetCoordinate)
                    .id(driveSessionID)
                    .frame(height: 170)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: shows3D)
        .animation(.smooth, value: showsStreetView)
        // With no 3D surface, the readout and scrubber only need four updates per second.
        .task(id: usesTimer) {
            guard usesTimer else { return }
            let clock = ContinuousClock()
            var previous = clock.now
            while replay.isPlaying {
                do {
                    try await clock.sleep(for: .milliseconds(250))
                } catch { return }
                guard !Task.isCancelled, usesTimer else { return }
                let now = clock.now
                replay.frame(previous.duration(to: now) / .seconds(1), stage: nil)
                previous = now
            }
        }
        .task(id: routeToLoad) {
            if let routeToLoad { await replay.load(routeToLoad) }
        }
        .onChange(of: replay.sampleIndex) { _, index in
            if replay.hasLoadedDrive(driveSessionID), index != selectedPointIndex { selectedPointIndex = index }
        }
        .onChange(of: selectedPointIndex, initial: true) { _, index in
            replay.seek(toSample: index)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { replay.isPlaying = false }
        }
        .onChange(of: driveSessionID) {
            replay.isPlaying = false
        }
    }

    private var stage: some View {
        let state = state
        let replay = replay
        let stage = VehicleStage.shared(for: spec)
        return VehicleStageView<DriveReplayPlaceholder, EmptyView>(
            spec: spec,
            state: state,
            stage: stage,
            accessibilityDescription: "Drive replay",
            onFrame: { stage, deltaTime in replay.frame(deltaTime, stage: stage) },
            onHotspot: nil,
            hotspotLabel: { _ in EmptyView() },
            placeholder: { DriveReplayPlaceholder() }
        )
        .id(ObjectIdentifier(stage))
        .aspectRatio(1.75, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 0.75)
        }
        .overlay(alignment: .topLeading) {
            DriveReplayReadout(replay: replay, driveSessionID: driveSessionID, fallback: state)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            playbackButtons
                .padding(10)
        }
    }

    /// Toggles for the two optional parts of the replay, remembered across launches.
    private var viewOptions: some View {
        HStack(spacing: 8) {
            Toggle("3D Replay", systemImage: "cube.fill", isOn: $shows3D)
            Toggle("Street View", systemImage: "binoculars.fill", isOn: $showsStreetView)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.footnote.weight(.semibold))
    }

    /// Speed, gear-less readout and playback buttons when only street view is showing.
    private var compactControls: some View {
        HStack(alignment: .center) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                let speed = replay.hasLoadedDrive(driveSessionID) ? replay.speedMPH : route[safe: selectedPointIndex]?.speed ?? 0
                Text(formattedNumber(speed, fractionLength: 0))
                    .font(.title.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text("mph")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            playbackButtons
        }
    }

    private var playbackButtons: some View {
        @Bindable var replay = replay
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Playback Speed", selection: $replay.speed) {
                        ForEach(DriveReplayController.Speed.allCases) { speed in
                            Text(speed.title).tag(speed)
                        }
                    }
                } label: {
                    Text(replay.speed.title)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed, \(replay.speed.title)")

                Button(replay.isPlaying ? "Pause" : "Play", systemImage: replay.isPlaying ? "pause.fill" : "play.fill") {
                    replay.isPlaying.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .accessibilityLabel(replay.isPlaying ? "Pause drive replay" : "Play drive replay")
            }
        }
        .disabled(route.count < 2 || !replay.hasLoadedDrive(driveSessionID))
    }

    @ViewBuilder
    private var matchStatus: some View {
        Group {
            if replay.isMatchingRoads {
                Label("Matching the drive to roads…", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            } else if replay.hasLoadedDrive(driveSessionID), let path = replay.path {
                if path.matchedFraction >= 0.5 {
                    Label("Following the road from Apple Maps", systemImage: "road.lanes")
                } else {
                    Label("Approximate road from recorded points", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var streetCoordinate: CLLocationCoordinate2D? {
        if replay.hasLoadedDrive(driveSessionID), let coordinate = replay.streetCoordinate {
            return coordinate
        }
        guard let point = route[safe: selectedPointIndex], let latitude = point.latitude, let longitude = point.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct DriveReplayReadout: View {
    let replay: DriveReplayController
    let driveSessionID: String?
    let fallback: VehicleStageState

    var body: some View {
        let isReady = replay.hasLoadedDrive(driveSessionID)
        VehicleDrivingReadout(
            speedMPH: isReady ? replay.speedMPH : fallback.speedMPH,
            gear: "D",
            units: nil,
            isSelfDriving: isReady ? replay.isSelfDriving : fallback.isSelfDriving
        )
    }
}

private struct DriveReplayPlaceholder: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading 3D replay")
    }
}
