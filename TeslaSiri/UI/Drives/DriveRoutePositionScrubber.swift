import AppIntents
import FleetKit
import SwiftUI

struct DriveRoutePositionScrubber: View {
    let sampleCount: Int
    @Binding var selectedSampleIndex: Int
    let driveSessionID: String?

    init(sampleCount: Int, selectedSampleIndex: Binding<Int>, driveSessionID: String? = nil) {
        self.sampleCount = sampleCount
        _selectedSampleIndex = selectedSampleIndex
        self.driveSessionID = driveSessionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Start", systemImage: "circle.fill")
                    .foregroundStyle(AppTheme.chargeGreen)

                Spacer()

                Text(routeProgress(index: selectedSampleIndex, count: sampleCount))
                    .font(.subheadline.weight(.semibold).monospacedDigit())

                Spacer()

                Label("End", systemImage: "flag.checkered")
                    .foregroundStyle(AppTheme.accent)
            }
            .font(.caption.weight(.medium))

            Slider(
                value: Binding(
                    get: {
                        Double(min(selectedSampleIndex, max(sampleCount - 1, 0)))
                    },
                    set: {
                        selectedSampleIndex = min(
                            max(Int($0.rounded()), 0),
                            max(sampleCount - 1, 0)
                        )
                    }
                ),
                in: 0...Double(max(sampleCount - 1, 0))
            ) {
                Text("Route position")
            }
            .disabled(sampleCount < 2)

            Text("Point \(min(selectedSampleIndex + 1, sampleCount)) of \(sampleCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .appEntityIdentifier(driveEntityIdentifier)
    }

    private var driveEntityIdentifier: EntityIdentifier? {
        guard let driveSessionID, !driveSessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: driveSessionID)
    }
}

struct DriveRoutePositionSummary: View {
    let point: FleetRoutePoint
    let index: Int
    let count: Int
    let driveSessionID: String?
    let units: String?

    init(point: FleetRoutePoint, index: Int, count: Int, driveSessionID: String? = nil, units: String? = nil) {
        self.point = point
        self.index = index
        self.count = count
        self.driveSessionID = driveSessionID
        self.units = units
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
            spacing: 10
        ) {
            DriveMetricTile(
                title: "Speed",
                value: formattedSpeed(mph: point.speed, units: units, fractionLength: 0),
                systemImage: "speedometer"
            )
            DriveMetricTile(
                title: "Progress",
                value: routeProgress(index: index, count: count),
                systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
            )
        }
        .appEntityIdentifier(driveEntityIdentifier)
    }

    private var driveEntityIdentifier: EntityIdentifier? {
        guard let driveSessionID, !driveSessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: driveSessionID)
    }
}

private func routeProgress(index: Int, count: Int) -> String {
    guard count > 1 else {
        return "--"
    }
    let percent = Double(index) / Double(count - 1) * 100
    return formattedPercent(percent)
}
