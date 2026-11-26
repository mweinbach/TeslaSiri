import AppIntents
import FleetKit
import SwiftUI

struct VehiclePickerCard: View {
    let vehicles: [FleetVehicle]
    let selectedVIN: String?
    let onSelect: (String) -> Void

    var body: some View {
        if vehicles.isEmpty {
            CardContainer(title: "Vehicles", systemImage: "car.2.fill") {
                Text("No vehicles linked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your vehicles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vehicles) { vehicle in
                            Button {
                                onSelect(vehicle.vin)
                            } label: {
                                VehicleChip(
                                    name: vehicle.name,
                                    vin: vehicle.vin,
                                    batteryLevel: vehicle.latest?.batteryLevel,
                                    chargingState: vehicle.latest?.chargingState,
                                    isLocked: vehicle.latest?.locked,
                                    isSelected: selectedVIN == vehicle.vin
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selectedVIN == vehicle.vin ? Text("Selected") : Text(""))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }
}

private struct VehicleChip: View {
    let name: String
    let vin: String
    let batteryLevel: Double?
    let chargingState: String?
    let isLocked: Bool?
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var isCharging: Bool {
        chargingState?.localizedCaseInsensitiveContains("charging") == true
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(
                    isSelected ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(formattedPercent(batteryLevel))
                        .monospacedDigit()

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(isSelected ? Color.white : Color.orange)
                    }

                    if let isLocked {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.84) : Color(uiColor: .secondaryLabel))
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.90))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 156, alignment: .leading)
        .background(
            isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.white.opacity(0.16)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                    lineWidth: 0.75
                )
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .shadow(
            color: Color.black.opacity(isSelected ? 0.12 : 0.04),
            radius: isSelected ? 10 : 5,
            y: isSelected ? 5 : 2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), VIN ending \(String(vin.suffix(6)))")
        .appEntityIdentifier(EntityIdentifier(for: VehicleEntity.self, identifier: vin))
    }
}

#Preview("Multiple vehicles") {
    ZStack {
        AppScreenBackground()

        VehiclePickerCard(
            vehicles: PreviewData.vehicles,
            selectedVIN: PreviewData.vin1,
            onSelect: { _ in }
        )
        .padding()
    }
}

#Preview("Empty") {
    ZStack {
        AppScreenBackground()

        VehiclePickerCard(vehicles: [], selectedVIN: nil, onSelect: { _ in })
            .padding()
    }
}

#Preview("Single vehicle") {
    ZStack {
        AppScreenBackground()

        VehiclePickerCard(
            vehicles: [PreviewData.vehicles[0]],
            selectedVIN: PreviewData.vin1,
            onSelect: { _ in }
        )
        .padding()
    }
}
