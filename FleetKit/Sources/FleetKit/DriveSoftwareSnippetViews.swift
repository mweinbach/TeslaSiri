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
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            if let minutes = drive.durationMinutes {
                                Text(FleetKitFormatting.durationMinutes(minutes))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
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
                        let pctText = FleetKitFormatting.percent(apPct)
                        Label {
                            Text("\(pctText) Autopilot", bundle: .module, comment: "Autopilot percentage badge on drive card")
                        } icon: {
                            Image(systemName: "steeringwheel")
                        }
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
            .accessibilityLabel(Text("Previous drive", bundle: .module, comment: "Accessibility label for previous drive button"))

            Text(verbatim: "\(selectedIndex + 1)/\(allDrives.count)")
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
            .accessibilityLabel(Text("Next drive", bundle: .module, comment: "Accessibility label for next drive button"))
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
                    Text(drive.startAddress ?? String(localized: "Start location", bundle: .module, comment: "Fallback start address on drive timeline"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(drive.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drive.endAddress ?? String(localized: "Destination", bundle: .module, comment: "Fallback destination address on drive timeline"))
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
                        Label {
                            HStack(spacing: 3) {
                                Text(FleetKitFormatting.percent(startSOC))
                                Image(systemName: "arrow.forward")
                                    .font(.caption2.weight(.semibold))
                                Text(FleetKitFormatting.percent(endSOC))
                            }
                        } icon: {
                            Image(systemName: "battery.75percent")
                        }
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        if let energy = drive.energyUsedKWH {
                            let kwh = FleetKitFormatting.energyKWH(energy)
                            Text("\(kwh) used", bundle: .module, comment: "Energy used during a drive")
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
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(height: 6)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                if let efficiency = drive.efficiencyText {
                    snippetMetricPill(
                        icon: "leaf.fill",
                        tint: .green,
                        value: efficiency,
                        label: String(localized: "Efficiency", bundle: .module, comment: "Drive efficiency metric label")
                    )
                }
                if let avg = drive.avgSpeedMPH {
                    let speedLabel: String = if let maxSpeed = drive.maxSpeedMPH {
                        String(
                            localized: "Avg • \(FleetKitFormatting.speed(mph: maxSpeed)) top",
                            bundle: .module,
                            comment: "Drive speed pill subtitle combining average label and top speed"
                        )
                    } else {
                        String(localized: "Avg", bundle: .module, comment: "Abbreviated average speed label")
                    }
                    snippetMetricPill(
                        icon: "speedometer",
                        tint: .blue,
                        value: FleetKitFormatting.speed(mph: avg),
                        label: speedLabel
                    )
                }
                if let ap = drive.autopilotDistanceMiles, ap > 0.05 {
                    snippetMetricPill(
                        icon: "steeringwheel",
                        tint: .cyan,
                        value: FleetKitFormatting.distance(miles: ap, fractionLength: 1),
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
                    .minimumScaleFactor(0.75)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                    Label {
                        Text("Apple Maps", bundle: .module, comment: "Button to open drive route in Apple Maps")
                    } icon: {
                        Image(systemName: "map.fill")
                    }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(intent: OpenDriveIntent(target: drive)) {
                Label {
                    Text("3D Replay", bundle: .module, comment: "Button to open 3D drive replay in the app")
                } icon: {
                    Image(systemName: "play.fill")
                }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
                Text("No Matching Drives", bundle: .module, comment: "Empty state title when no drives match")
                    .font(.subheadline.weight(.semibold))
                Text("No completed drives matched for \(vehicleName).", bundle: .module, comment: "Empty state description when no drives match")
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
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "v\(version)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.16), in: Capsule())
            }

            if notes.isEmpty {
                Text("No release notes available for version \(version).", bundle: .module, comment: "Empty state when no release notes exist for a software version")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(3)) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if let subtitle = note.subtitle,
                               !subtitle.isEmpty,
                               subtitle.caseInsensitiveCompare(note.title) != .orderedSame {
                                Text(subtitle)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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

                if notes.count > 3 {
                    let remaining = notes.count - 3
                    Text("+^[\(remaining) more feature update](inflect: true)", bundle: .module, comment: "Count of additional release notes not shown on the Siri card")
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
                    .lineLimit(1)
                Spacer()
                if let current = software.currentVersion {
                    Text("Installed \(current)", bundle: .module, comment: "Badge showing currently installed vehicle software version")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
                        if software.installPercent ?? 0 > 0 {
                            Text("Installing Update", bundle: .module, comment: "Progress label while vehicle software update is installing")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Downloaded", bundle: .module, comment: "Progress label for software update download progress")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(FleetKitFormatting.percent(Int(progress.rounded())))
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
                            Label {
                                Text("Install Update", bundle: .module, comment: "Button to start installing an available software update")
                            } icon: {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if canCancelUpdate {
                        Button(intent: cancelIntent) {
                            Label {
                                Text("Cancel", bundle: .module, comment: "Button to cancel a scheduled software update")
                            } icon: {
                                Image(systemName: "xmark.circle.fill")
                            }
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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
