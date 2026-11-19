import SwiftUI

/// Frequent destinations as a row of chips (icon, name, visit count). Selecting a place
/// filters the drives to that place; selecting it again clears the filter.
struct DrivePlacesStrip: View {
    let places: [DrivePlace]
    let isIndexing: Bool
    @Binding var selectedPlaceID: String?
    let onEditNickname: (DrivePlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Places")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if isIndexing {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Finding places")
                }
                Spacer()
                if selectedPlaceID != nil {
                    Button("Show All") {
                        selectedPlaceID = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if places.isEmpty {
                Text(isIndexing ? "Finding the places you drive to…" : "No places found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(places) { place in
                            PlaceChip(
                                place: place,
                                isSelected: place.id == selectedPlaceID,
                                onEditNickname: { onEditNickname(place) }
                            ) {
                                selectedPlaceID = place.id == selectedPlaceID ? nil : place.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(.snappy, value: selectedPlaceID)
    }
}

private struct PlaceChip: View {
    let place: DrivePlace
    let isSelected: Bool
    let onEditNickname: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Menu {
            Button("Edit Nickname", systemImage: "pencil", action: onEditNickname)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: place.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(place.visitCount == 1 ? "1 visit" : "\(place.visitCount) visits")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(AppTheme.surface))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? .clear : AppTheme.hairline, lineWidth: 0.75)
            }
            .contentShape(.capsule)
        } primaryAction: {
            onSelect()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(place.displayName)
        .accessibilityValue(place.visitCount == 1 ? "1 visit" : "\(place.visitCount) visits")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Edit Nickname", onEditNickname)
    }
}
