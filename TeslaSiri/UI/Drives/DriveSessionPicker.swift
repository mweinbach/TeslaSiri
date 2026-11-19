import AppIntents
import FleetKit
import SwiftUI

struct DriveSessionPicker: View {
    let drives: [FleetDriveSession]
    let endpointAddresses: [String: DriveEndpointAddresses]
    @Binding var selectedSessionID: String
    var title: String = "Recent drives"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(drives) { drive in
                        Button {
                            selectedSessionID = drive.sessionID
                        } label: {
                            Text(menuLabel(for: drive))
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedDrive.map(menuLabel(for:)) ?? "Select a drive")
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .appSurface(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(drives) { drive in
                                Button {
                                    selectedSessionID = drive.sessionID
                                } label: {
                                    DriveSessionChip(
                                        drive: drive,
                                        endpointAddresses: endpointAddresses[drive.sessionID],
                                        isSelected: selectedSessionID == drive.sessionID
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Drive from \(drive.startedAtDate.formatted(date: .abbreviated, time: .shortened))")
                                .accessibilityValue(driveEndpointSummary(drive, endpointAddresses: endpointAddresses[drive.sessionID]))
                                .accessibilityAddTraits(selectedSessionID == drive.sessionID ? .isSelected : [])
                                .id(drive.sessionID)
                            }
                        }
                        .padding(3)
                    }
                    .onChange(of: selectedSessionID, initial: true) { _, newID in
                        guard !newID.isEmpty else { return }
                        withAnimation(.snappy(duration: 0.22)) {
                            scrollProxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var selectedDrive: FleetDriveSession? {
        drives.first { $0.sessionID == selectedSessionID } ?? drives.first
    }

    private func menuLabel(for drive: FleetDriveSession) -> String {
        let date = drive.startedAtDate.formatted(date: .abbreviated, time: .shortened)
        let summary = driveEndpointSummary(drive, endpointAddresses: endpointAddresses[drive.sessionID])
        return "\(date) · \(summary)"
    }
}

struct DriveSessionChip: View {
    let drive: FleetDriveSession
    let endpointAddresses: DriveEndpointAddresses?
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.duoPosture) private var duoPosture

    private var compactDate: String {
        drive.startedAtDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "steeringwheel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                Text(compactDate)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }

            Text(driveEndpointSummary(drive, endpointAddresses: endpointAddresses))
                .font(.caption)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formattedNumber(drive.distanceMiles, fractionLength: 1, suffix: " mi"))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()

                if let durationMS = drive.durationMS, durationMS > 0 {
                    Text(formattedDuration(milliseconds: durationMS))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(13)
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 320 : (duoPosture.prefersCompactHero ? 216 : 238),
            alignment: .leading
        )
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 148 : 106, alignment: .leading)
        .appSurface(cornerRadius: AppTheme.tileCornerRadius)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.tileCornerRadius, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.05))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: AppTheme.tileCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .appEntityIdentifier(EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID))
    }
}
