import SwiftUI

/// What Lodestar's numbers can and cannot be trusted for.
struct AccuracyNotesView: View {
    private struct Note: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    private static let notes = [
        Note(title: "Where things are",
             text: "The Sun, Moon and planets come from published solar-system theories (VSOP87 for the planets, a "
                 + "Meeus-based lunar theory) and are good to well under an arcminute. Stars and deep-sky objects use "
                 + "catalog positions with proper motion, precession, nutation, aberration and atmospheric "
                 + "refraction applied. The star catalog reaches magnitude 6.5; the deep-sky catalog holds the "
                 + "Messier objects, named objects and the brighter NGC and IC objects."),
        Note(title: "Where the camera points",
             text: "The phone's compass and gyroscope tell Lodestar where the camera points. A compass is typically "
                 + "good to a few degrees and is disturbed by metal and electronics: tripod heads, camera bodies, "
                 + "lens motors, even a magnetic case. Aligning on a bright star or the Moon (Aim \u{25B8} Align) "
                 + "corrects the heading and the tilt of your bracket and shows the error that remains. Gyro Lock "
                 + "ignores the compass after the first heading and drifts slowly."),
        Note(title: "True north",
             text: "True north comes from the World Magnetic Model 2025, valid until the end of 2029. Its declination "
                 + "is typically within about half a degree. Near the magnetic poles a compass cannot be trusted at "
                 + "all."),
        Note(title: "Your location and the clock",
             text: "Sky positions depend on where you are and what time it is. An approximate location is accurate "
                 + "enough: a few kilometers change a position by well under a tenth of a degree. Keep the date, time "
                 + "and time zone of your iPhone on automatic."),
        Note(title: "Refraction",
             text: "The atmosphere lifts objects near the horizon. Lodestar corrects for it with the temperature and "
                 + "pressure in Settings. Right at the horizon the real refraction varies with the weather by several "
                 + "arcminutes."),
        Note(title: "Exposure advice",
             text: "Exposure limits are rules of thumb. The NPF rule takes aperture and pixel size into account; the "
                 + "500 rule is optimistic for high-resolution sensors. Check the stars in your first test frame."),
    ]

    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            ForEach(Self.notes) { note in
                SettingsSection(title: note.title) {
                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .themedList(palette)
        .navigationTitle("Accuracy Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
