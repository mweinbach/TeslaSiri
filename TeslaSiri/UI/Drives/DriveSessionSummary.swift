import AppIntents
import FleetKit
import SwiftUI

struct DriveSessionSummary: View {
    let drive: FleetDriveSession
    let endpointAddresses: DriveEndpointAddresses?
    let hasRoute: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 132), spacing: 10)]
    }

    var body: some View {
        CardContainer(title: "Trip summary", systemImage: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: metricColumns,
                    spacing: 10
                ) {
                    DriveMetricTile(
                        title: "Distance",
                        value: formattedNumber(drive.distanceMiles, fractionLength: 1, suffix: " mi"),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    DriveMetricTile(
                        title: "Duration",
                        value: formattedDuration(milliseconds: drive.durationMS),
                        systemImage: "timer"
                    )
                    DriveMetricTile(
                        title: "Average",
                        value: formattedNumber(drive.avgSpeedMPH, fractionLength: 0, suffix: " mph"),
                        systemImage: "speedometer"
                    )
                    DriveMetricTile(
                        title: "Route",
                        value: hasRoute ? "Mapped" : "Missing",
                        systemImage: "map"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    DriveEndpointRow(
                        title: "Start",
                        address: endpointAddresses?.start ?? drive.startAddress ?? "Unknown location",
                        systemImage: "circle.fill",
                        tint: AppTheme.chargeGreen,
                        showsTrailingConnector: true
                    )
                    DriveEndpointRow(
                        title: "Destination",
                        address: endpointAddresses?.end ?? drive.endAddress ?? "Unknown location",
                        systemImage: "flag.checkered",
                        tint: AppTheme.accent,
                        showsTrailingConnector: false
                    )
                }
            }
        }
        .appEntityIdentifier(EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID))
    }
}

private struct DriveEndpointRow: View {
    let title: String
    let address: String
    let systemImage: String
    let tint: Color
    let showsTrailingConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())

                if showsTrailingConnector {
                    Rectangle()
                        .fill(AppTheme.hairline)
                        .frame(width: 1.5, height: 18)
                        .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(address)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, showsTrailingConnector ? 10 : 0)

            Spacer(minLength: 0)
        }
    }
}
