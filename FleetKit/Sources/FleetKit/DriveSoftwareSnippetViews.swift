import AppIntents
import Foundation
import SwiftUI

public struct DriveSnippetView: View {
    public let drive: DriveEntity
    public let allDrives: [DriveEntity]
    public let selectedIndex: Int
    public let sessionKey: String
    public let vehicleName: String?
    public let mapData: SiriRenderedMapData?

    public init(
        drive: DriveEntity,
        allDrives: [DriveEntity]? = nil,
        selectedIndex: Int = 0,
        sessionKey: String = "latest",
        vehicleName: String? = nil,
        mapData: SiriRenderedMapData? = nil
    ) {
        self.drive = drive
        self.allDrives = allDrives ?? [drive]
        self.selectedIndex = selectedIndex
        self.sessionKey = sessionKey
        self.vehicleName = vehicleName
        self.mapData = mapData
    }

    private var fallbackPoints: [FleetDriveRoutePoint] {
        if let pts = mapData?.points, !pts.isEmpty {
            return pts
        }
        var pts: [FleetDriveRoutePoint] = []
        if let sLat = drive.startLatitude, let sLon = drive.startLongitude {
            pts.append(FleetDriveRoutePoint(latitude: sLat, longitude: sLon))
        }
        if let eLat = drive.endLatitude, let eLon = drive.endLongitude {
            pts.append(FleetDriveRoutePoint(latitude: eLat, longitude: eLon))
        }
        return pts
    }

    private var currentStyle: SiriMapVisualStyle {
        mapData?.style ?? .standard
    }

    private var autopilotSharePercent: Int? {
        guard let ap = drive.autopilotDistanceMiles, ap > 0.05,
              let total = drive.distanceMiles, total > 0.1 else {
            return nil
        }
        return min(max(Int((ap / total * 100).rounded()), 1), 100)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            routeMapHero

            routeEndpointsTimeline

            telemetryBentoSection

            actionRow
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: DriveEntity.self, identifier: drive.id))
    }

    // MARK: - Embedded Apple Maps Route Hero

    private var routeMapHero: some View {
        ZStack {
            Group {
                if let mapImage = mapData?.swiftUIImage {
                    mapImage
                        .resizable()
                        .scaledToFill()
                } else {
                    SiriVectorRouteFallbackView(points: fallbackPoints)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.45),
                    .clear,
                    .black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if let vehicleName, !vehicleName.isEmpty {
                        Label(vehicleName, systemImage: "car.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                    }

                    if let tag = drive.tag, !tag.isEmpty {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.75), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    Button(intent: ToggleSnippetMapStyleIntent(scope: "drive")) {
                        Label(currentStyle.badgeLabel, systemImage: currentStyle.badgeIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)

                Spacer()

                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(drive.distanceText)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)

                            if let minutes = drive.durationMinutes {
                                Text("\(minutes) min")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                            }
                        }

                        Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer(minLength: 4)

                    if allDrives.count > 1 {
                        driveCarouselStepper
                    } else if let apPct = autopilotSharePercent {
                        Label("\(apPct)% Autopilot", systemImage: "steeringwheel")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
        )
    }

    private var driveCarouselStepper: some View {
        let prevIndex = (selectedIndex - 1 + allDrives.count) % allDrives.count
        let nextIndex = (selectedIndex + 1) % allDrives.count

        return HStack(spacing: 6) {
            Button(intent: SelectSnippetItemIntent(sessionKey: sessionKey, targetIndex: prevIndex, cardType: "drive")) {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous drive")

            Text("\(selectedIndex + 1)/\(allDrives.count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)

            Button(intent: SelectSnippetItemIntent(sessionKey: sessionKey, targetIndex: nextIndex, cardType: "drive")) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next drive")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.62), in: Capsule())
    }

    // MARK: - Start -> End Route Timeline

    private var routeEndpointsTimeline: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 3) {
                Circle()
                    .fill(.green)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)

                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 1.5, height: 22)

                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drive.startAddress ?? "Start location")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(drive.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drive.endAddress ?? "Destination")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let endedAt = drive.endedAt {
                        Text(endedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Telemetry Bento Strip

    private var telemetryBentoSection: some View {
        VStack(spacing: 8) {
            if let startSOC = drive.startingBatteryPercent, let endSOC = drive.endingBatteryPercent {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("\(startSOC)% → \(endSOC)%", systemImage: "battery.75percent")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let energy = drive.energyUsedKWH {
                            Text(String(format: "%.1f kWh used", energy))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    let startFrac = Double(min(max(startSOC, 0), 100)) / 100.0
                    let endFrac = Double(min(max(endSOC, 0), 100)) / 100.0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                        FractionalCapsuleBar(fraction: max(startFrac, endFrac), minimumWidth: 4)
                            .fill(.orange.opacity(0.45))
                        FractionalCapsuleBar(fraction: min(startFrac, endFrac), minimumWidth: 4)
                            .fill(.green.gradient)
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                if let efficiency = drive.efficiencyText {
                    snippetMetricPill(icon: "leaf.fill", tint: .green, value: efficiency, label: "Efficiency")
                }
                if let avg = drive.avgSpeedMPH {
                    let maxPart = drive.maxSpeedMPH.map { " • \(Int($0.rounded())) top" } ?? ""
                    snippetMetricPill(
                        icon: "speedometer",
                        tint: .blue,
                        value: "\(Int(avg.rounded())) mph",
                        label: "Avg\(maxPart)"
                    )
                }
                if let ap = drive.autopilotDistanceMiles, ap > 0.05 {
                    snippetMetricPill(
                        icon: "steeringwheel",
                        tint: .cyan,
                        value: String(format: "%.1f mi", ap),
                        label: "Autopilot"
                    )
                }
            }
        }
    }

    private func snippetMetricPill(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let mapsURL = drive.appleMapsRouteURL {
                Link(destination: mapsURL) {
                    Label("Apple Maps", systemImage: "map.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(intent: OpenDriveIntent(target: drive)) {
                Label("3D Replay", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct EmptyDriveSnippetView: View {
    let vehicleName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "road.lanes")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Matching Drives")
                    .font(.subheadline.weight(.semibold))
                Text("No completed drives matched for \(vehicleName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

public struct ReleaseNotesSnippetView: View {
    public let vehicleName: String
    public let version: String
    public let notes: [ReleaseNoteEntity]

    public init(vehicleName: String, version: String, notes: [ReleaseNoteEntity]) {
        self.vehicleName = vehicleName
        self.version = version
        self.notes = notes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(vehicleName, systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("v\(version)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.16), in: Capsule())
            }

            if notes.isEmpty {
                Text("No release notes available for version \(version).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(4)) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                            if let subtitle = note.subtitle,
                               !subtitle.isEmpty,
                               subtitle.caseInsensitiveCompare(note.title) != .orderedSame {
                                Text(subtitle)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        if let details = note.details,
                           !details.isEmpty,
                           details.caseInsensitiveCompare(note.subtitle ?? "") != .orderedSame {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .appEntityIdentifier(EntityIdentifier(for: ReleaseNoteEntity.self, identifier: note.id))
                }

                if notes.count > 4 {
                    Text("+\(notes.count - 4) more feature update\(notes.count - 4 == 1 ? "" : "s")")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }
}

public struct SoftwareSnippetView: View {
    public let software: SoftwareUpdateEntity

    public init(software: SoftwareUpdateEntity) {
        self.software = software
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(software.vehicleName, systemImage: "car.fill")
                    .font(.headline)
                Spacer()
                if let current = software.currentVersion {
                    Text("Installed \(current)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Image(systemName: software.updateAvailable ? "arrow.down.circle.dotted" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(software.updateAvailable ? AnyShapeStyle(.tint) : AnyShapeStyle(.green))

                VStack(alignment: .leading, spacing: 2) {
                    Text(software.headline)
                        .font(.subheadline.weight(.bold))
                    Text(software.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let progress = activeProgressPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(software.installPercent ?? 0 > 0 ? "Installing Update" : "Downloaded")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress.rounded()))%")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                    }
                    ProgressView(value: min(max(progress, 0), 100), total: 100)
                }
            }

            if software.updateAvailable || software.installable || canCancelUpdate {
                HStack(spacing: 8) {
                    if software.updateAvailable || software.installable {
                        Button(intent: installIntent) {
                            Label("Install Update", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if canCancelUpdate {
                        Button(intent: cancelIntent) {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: SoftwareUpdateEntity.self, identifier: software.id))
    }

    private var activeProgressPercent: Double? {
        if let install = software.installPercent, install > 0 { return Double(install) }
        if let download = software.downloadPercent, download > 0, software.updateAvailable { return Double(download) }
        return nil
    }

    private var vehicle: VehicleEntity {
        VehicleEntity(id: software.vin, name: software.vehicleName)
    }

    private var installIntent: InstallSoftwareUpdateIntent {
        let intent = InstallSoftwareUpdateIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var cancelIntent: CancelSoftwareUpdateIntent {
        let intent = CancelSoftwareUpdateIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var canCancelUpdate: Bool {
        software.status?.localizedCaseInsensitiveContains("scheduled") == true
            || software.status?.localizedCaseInsensitiveContains("pending") == true
            || software.status?.localizedCaseInsensitiveContains("countdown") == true
    }
}
