import SwiftUI

struct ChargingCard: View {
    let sessions: [FleetChargeSession]

    var body: some View {
        CardContainer(title: "Charging", systemImage: "bolt.fill") {
            if sessions.isEmpty {
                Text("No active charging sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sessions) { session in
                        ChargingSessionRow(
                            status: session.status,
                            startedAt: session.startedAtDate,
                            energyAddedKWH: session.energyAddedKWH,
                            avgPowerKW: session.avgPowerKW
                        )
                        if session.id != sessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct ChargingSessionRow: View {
    let status: String?
    let startedAt: Date
    let energyAddedKWH: Double?
    let avgPowerKW: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    status.map(humanizedStatus) ?? String(localized: "Charging", comment: "Default label for an active charging session"),
                    systemImage: "bolt.fill"
                )
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(startedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ChargingMetric(
                    title: "Energy added",
                    value: formattedEnergyKWH(energyAddedKWH),
                    systemImage: "battery.100.bolt"
                )
                ChargingMetric(
                    title: "Average power",
                    value: formattedPowerKW(avgPowerKW),
                    systemImage: "bolt"
                )
            }
        }
    }
}

private struct ChargingMetric: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("With sessions") {
    ChargingCard(sessions: PreviewData.chargeSessions)
        .padding()
        .background(AppScreenBackground())
}

#Preview("Empty") {
    ChargingCard(sessions: [])
        .padding()
        .background(AppScreenBackground())
}

#Preview("Single session") {
    ChargingCard(sessions: [PreviewData.chargeSessions[0]])
        .padding()
        .background(AppScreenBackground())
}
