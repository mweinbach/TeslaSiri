import CoreLocation
import MapKit
import SwiftUI

/// Apple Maps Look Around imagery that follows the car through a drive replay.
///
/// Each new position loads a Look Around still and crossfades it over the previous one, so the
/// view keeps moving with the car and never flashes empty while the next frame loads. Spots
/// without imagery keep the last frame. Tapping opens the interactive Look Around viewer at the
/// current spot.
struct DriveStreetView: View {
    let coordinate: CLLocationCoordinate2D?

    @Environment(\.colorScheme) private var colorScheme
    @State private var frame: StreetFrame?
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var isShowingViewer = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.insetSurface

                if let frame {
                    Image(uiImage: frame.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .id(frame.id)
                        .transition(.opacity)
                } else if hasSearched && !isLoading {
                    Label("No street view here yet", systemImage: "binoculars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .animation(.easeInOut(duration: 0.6), value: frame?.id)
            .task(id: TaskKey(coordinate: coordinateKey, size: proxy.size, colorScheme: colorScheme)) {
                await load(size: proxy.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if frame != nil {
                Label("Look Around", systemImage: "binoculars.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLoading && frame != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if frame != nil { isShowingViewer = true }
        }
        .lookAroundViewer(isPresented: $isShowingViewer, initialScene: frame?.scene)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Street view at the car's position")
        .accessibilityHint(frame == nil ? Text("") : Text("Opens Look Around"))
        .accessibilityAddTraits(frame == nil ? [] : .isButton)
    }

    private func load(size: CGSize) async {
        guard !Task.isCancelled else { return }
        guard let coordinate, size.width > 10, size.height > 10 else {
            isLoading = false
            hasSearched = coordinate == nil
            return
        }
        // Let fast movement settle a little so only positions the car lingers at load.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        isLoading = true
        defer {
            if !Task.isCancelled {
                isLoading = false
                hasSearched = true
            }
        }
        guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene,
              !Task.isCancelled else { return }
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot,
              !Task.isCancelled else { return }
        frame = StreetFrame(image: snapshot.image, scene: scene)
    }

    /// About 10 m of precision, so tiny moves don't start new requests.
    private var coordinateKey: String {
        guard let coordinate else { return "none" }
        return String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    private struct TaskKey: Equatable {
        let coordinate: String
        let size: CGSize
        let colorScheme: ColorScheme
    }

    private struct StreetFrame {
        let id = UUID()
        let image: UIImage
        let scene: MKLookAroundScene
    }
}
