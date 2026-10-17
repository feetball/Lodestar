import MapKit
import SwiftUI
import LodestarKit

/// A satellite map on which the user taps to drop a pin for a new observing site.
///
/// In night mode the map, which draws its own colours, is covered by a dark-red scrim; the readout and the button
/// below it use the palette. The pin is only a convenience: the site editor also takes typed coordinates.
struct MapSitePicker: View {
    /// Latitude/longitude span of the initial view around a chosen position (about 55 km).
    private static let siteSpan = 0.5
    /// Span of the initial view around the fallback centre (a region).
    private static let regionSpan = 8.0
    /// Latitude beyond which the initial view is not centred, in degrees.
    private static let polarLimit = 80.0
    /// Dark red laid over the map at night; 12 % of the original colours still show through.
    private static let nightScrim = Color(red: 0.55, green: 0, blue: 0).opacity(0.88)

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private let onSelect: (GeographicLocation) -> Void
    @State private var position: MapCameraPosition
    @State private var selection: GeographicLocation?

    /// - Parameters:
    ///   - initialLocation: The pin to start with, if any; the map opens around it.
    ///   - fallbackCenter: Where to open the map when there is no pin, e.g. the current observer.
    ///   - onSelect: Called with the pinned position when the user confirms.
    init(initialLocation: GeographicLocation?, fallbackCenter: GeographicLocation?,
         onSelect: @escaping (GeographicLocation) -> Void) {
        self.onSelect = onSelect
        _selection = State(initialValue: initialLocation)
        if let initialLocation {
            _position = State(initialValue: Self.cameraPosition(around: initialLocation, span: Self.siteSpan))
        } else if let fallbackCenter {
            _position = State(initialValue: Self.cameraPosition(around: fallbackCenter, span: Self.regionSpan))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let selection {
                    Marker("Site", coordinate: Self.coordinate(of: selection))
                        .tint(palette.accent)
                }
            }
            .mapStyle(.hybrid)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture(coordinateSpace: .local) { point in
                if let coordinate = proxy.convert(point, from: .local),
                   let location = GeographicLocation.validated(latitude: coordinate.latitude,
                                                               longitude: coordinate.longitude) {
                    selection = location
                }
            }
        }
        .overlay {
            if palette.isNight {
                Self.nightScrim
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            confirmationBar
        }
        .navigationTitle("Choose Site")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var confirmationBar: some View {
        VStack(spacing: 10) {
            Text(selection.map(SettingsFormat.coordinates(of:)) ?? "Tap the map to drop a pin.")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
            Button("Use This Location") {
                if let selection {
                    onSelect(selection)
                    dismiss()
                }
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(selection == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
    }

    private static func coordinate(of location: GeographicLocation) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    /// A view of `span` degrees around `location`. The center stays clear of the poles so that the view never
    /// reaches past them, where MapKit has no valid region.
    private static func cameraPosition(around location: GeographicLocation, span: Double) -> MapCameraPosition {
        let latitude = AstroMath.clamp(location.latitude, -polarLimit, polarLimit)
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: location.longitude)
        return .region(MKCoordinateRegion(center: center,
                                          span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    }
}
