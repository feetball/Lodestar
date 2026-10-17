import SwiftUI
import LodestarKit

/// The objects offered first when choosing a target: the Moon, the planets above the horizon, the Milky Way core
/// and the pole star of the observer's hemisphere (Polaris, or the south celestial pole).
enum AimQuickPicks {
    struct Pick: Identifiable {
        let object: CelestialObject
        let title: String
        var id: String { object.id }
    }

    private static let planetIDs = ["planet.venus", "planet.jupiter", "planet.saturn", "planet.mars", "planet.mercury"]
    private static let galacticCenterID = "special.galacticCenter"
    private static let polarisID = "star.hip11767"
    private static let southCelestialPoleID = "special.scp"

    /// - Parameters:
    ///   - snapshot: The current sky, when known; planets below the horizon are left out and the pole pick
    ///     follows the observer's hemisphere.
    ///   - planetLimit: The most planets offered, the brightest first.
    @MainActor
    static func picks(catalog: CatalogService, snapshot: SkySnapshot?, planetLimit: Int) -> [Pick] {
        let bodies = snapshot?.bodies
        var picks: [Pick] = []
        func add(_ id: String, title: String? = nil) {
            if let object = catalog.object(id: id) {
                picks.append(Pick(object: object, title: title ?? object.name))
            }
        }
        add("moon")
        let visible: [String]
        if let bodies {
            let planets = bodies.filter { planetIDs.contains($0.object.id) && $0.horizontal.altitude > 0 }
            visible = planets.sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }.map(\.object.id)
        } else {
            visible = planetIDs
        }
        visible.prefix(planetLimit).forEach { add($0) }
        add(galacticCenterID, title: "Milky Way core")
        if let latitude = snapshot?.observer.location.latitude, latitude < 0 {
            add(southCelestialPoleID)
        } else {
            add(polarisID)
        }
        return picks
    }
}

/// A quick pick as a capsule button.
struct AimQuickPickButton: View {
    let pick: AimQuickPicks.Pick
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Label(pick.title, systemImage: pick.object.category.systemImageName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(palette.accent)
                .background(Capsule().fill(palette.surfaceRaised))
                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
