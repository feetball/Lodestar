import Foundation

extension HelpContent {
    private static let mounts = HelpTopic(
        topic: .mounts, category: .equipment, title: "GoTo mounts", systemImage: "antenna.radiowaves.left.and.right",
        summary: "Slew a GoTo mount to your target over Wi-Fi.",
        keywords: ["telescope", "slew", "wifi", "onstep", "synscan", "nexstar", "alpaca", "simulated"],
        blocks: [
            .paragraph("A GoTo mount turns the camera to your target for you. Lodestar connects to it over Wi-Fi and works with OnStep and LX200 mounts, Celestron NexStar and SynScan hand controllers, ASCOM Alpaca, and the Sky-Watcher AZ-GTi and Star Adventurer GTi. Switch the Sky-Watcher mounts on at their home position, and align them on one to three stars before the first **Go to**. For NexStar and SynScan, align on the hand controller first. When Lodestar goes to the background, it stops the mount and disconnects."),
            .steps([
                "In **Settings**, under **GoTo Mount**, tap **Mount Control**. Choose your mount, then tap **Connect**.",
                "When iOS asks whether Lodestar may find devices on your local network, allow it. Lodestar talks to the mount on your local network only. Nothing is sent to the internet.",
                "In **Aim**, tap **Mount**. The button appears after the first connection. Its strip shows the mount\u{2019}s name and where it points.",
                "**Go to** and **Sync** ask for confirmation first. **Nudge** opens the arrows. **Stop** is always there.",
            ]),
            .tip("To practice without hardware, tap **Simulated OnStep mount** or **Simulated Sky-Watcher mount** under **Connect**."),
            .caution("Lodestar cannot see cables, people or obstacles, and a mount can swing through a wide arc. Keep hands and cables clear before a slew, and tap **Stop** if anything looks wrong. Lodestar never slews to the Sun, but it does not check the path, so do not use GoTo by day unless your optics have a certified solar filter."),
        ],
        related: [.alignment, .aimScreen, .troubleshooting])

    private static let nightMode = HelpTopic(
        topic: .nightMode, category: .more, title: "Night mode", systemImage: "moon.stars",
        summary: "Red on black and a dim screen, to keep night vision.",
        keywords: ["red", "dark", "dim", "sunset", "filter", "brightness", "adaptation", "screen"],
        blocks: [
            .paragraph("A bright screen spoils your dark adaptation, the way your eyes adjust to the dark. Night mode draws Lodestar in pure red on black, and by default it also dims the screen while it is on. The status bar is hidden while night mode is on."),
            .steps([
                "Open **Settings** \u{25B8} **Night Mode**, and choose **Off**, **On** or **After Sunset**. The default is **After Sunset**, which switches on by itself when the Sun is more than 6\u{00B0} below the horizon.",
                "On the Aim screen, tap the night button to step through the three. It reads **Night off**, **Night on** or **Night auto**.",
            ]),
            .tip("Turn on **Camera preview at night** to see the camera picture in red too. It is brighter than the sky alone, so it costs some night vision."),
            .caution("Apps cannot tint the keyboard, menus or alerts, so they keep their normal colors. For a fully red screen, set up iOS **Color Filters**: go to **Settings** \u{25B8} **Accessibility** \u{25B8} **Display & Text Size** \u{25B8} **Color Filters**, turn on **Color Tint**, drag **Intensity** and **Hue** all the way to the right, then go to **Accessibility Shortcut** and choose **Color Filters**. Triple-click the side button to switch the red screen on and off."),
        ],
        related: [.gettingStarted, .troubleshooting])

    private static let onlineData = HelpTopic(
        topic: .onlineData, category: .more, title: "Optional online data", systemImage: "arrow.down.circle",
        summary: "Optional downloads for satellites, comets and cloud cover.",
        keywords: ["internet", "download", "satellites", "starlink", "comets", "clouds", "forecast", "network"],
        blocks: [
            .paragraph("Lodestar works fully offline. These optional downloads add satellite passes, Starlink streak warnings, comets and a cloud forecast. All are off until you switch them on in **Settings** \u{25B8} **Online Data**, and each one says what it sends. Each provider sees your IP address. Apart from these, the network is used only for the site map from Apple Maps and for the time-zone lookup when you add or edit a site."),
            .bullets([
                "**Satellite passes** show when the ISS and other bright satellites cross your sky, on the Tonight screen and in Aim. About 75 KB from CelesTrak.",
                "**Starlink streak warnings** warn in Aim when Starlink may cross your frame during an exposure. About 4.7 MB from CelesTrak, once a day, and only on Wi-Fi or another unmetered network.",
                "**Comets** join the object list, the sky chart and Aim. About 164 KB from the Minor Planet Center.",
                "**Cloud forecast** shows tonight\u{2019}s hourly cloud cover on the Tonight screen. MET Norway receives your location, rounded to about 10 km.",
            ]),
            .tip("**Update now** refreshes a feed. CelesTrak answers repeated requests for unchanged data with an error, so the satellite lists wait at least two hours between requests. When it is too soon, the button is grayed out and says when the next update is possible."),
            .caution("Switching a feed off deletes what it downloaded. If a feed shows **The last update failed.**, Lodestar keeps the data it already has. Wait, then try **Update now** again."),
        ],
        related: [.tonight, .troubleshooting])

    private static let widgets = HelpTopic(
        topic: .widgets, category: .more, title: "Widgets and Apple Watch", systemImage: "applewatch",
        summary: "Tonight at a glance on your Home Screen and your watch.",
        keywords: ["complication", "lock", "home", "glance", "moon", "milky", "smartwatch", "tonight"],
        blocks: [
            .paragraph("Widgets show tonight at a glance: when it gets dark, the Moon, when the Milky Way core (its bright center) is up, and the next event, for where you are. The iPhone has small and medium widgets for the Home Screen, and circular, rectangular and inline ones for the Lock Screen. On Apple Watch, the circular complication shows the Moon\u{2019}s phase, and the rectangular one shows the dark window, the Moon and the next event. A tap opens the **Tonight** tab. The widgets use your approximate location and work out the night on the device, with no network."),
            .steps([
                "Touch and hold the Home Screen or the Lock Screen, then tap the add button.",
                "Choose **Lodestar**, then the **Tonight** widget.",
                "On Apple Watch, edit the watch face and choose a Lodestar complication.",
            ]),
            .tip("The Apple Watch app also has a small **Tonight** screen of its own."),
        ],
        related: [.tonight, .onlineData])

    private static let troubleshooting = HelpTopic(
        topic: .troubleshooting, category: .more, title: "Troubleshooting", systemImage: "wrench.and.screwdriver",
        summary: "Fixes for the chips and messages that Aim shows.",
        keywords: ["problem", "fix", "wrong", "error", "compass", "drift", "alignment", "chip"],
        blocks: [
            .paragraph("Most problems show up as a chip at the top of the Aim screen. Find yours below."),
            .bullets([
                "**The arrows seem wrong, or the distance does not shrink.** Open **Settings** \u{25B8} **Mount** and check that the phone mount matches how the phone sits on the camera. Then open **Settings** \u{25B8} **About** \u{25B8} **Sensor Diagnostics**. With the phone upright and the camera facing north, the gravity check should read **PASS**. Finally, align on a star.",
                "**Compass poor** or **Magnetic interference**. Move away from metal and electronics, which can pull the compass off by several degrees. Then set **Heading source** to **Gyro Lock** in **Settings** \u{25B8} **Mount** and align on a star. Changing the heading source clears the alignment.",
                "**Not aligned**. Tap **Align** on the Aim screen. Choose a bright star or planet, center it in the camera, then tap **Centered \u{2014} Sync**.",
                "**Set heading: align on a star**. Gyro Lock has no heading yet. One alignment sets it.",
                "**The heading drifts**. Gyro Lock drifts slowly. Align on a star again.",
                "**Camera off \u{00B7} Settings**. Camera access is off in iOS. Tap the chip to open the iOS Settings and allow the camera. The virtual sky still works.",
                "**Approx. location**. iOS gave Lodestar an approximate location. Approximate is fine for the sky. To use a site instead, choose one in **Settings** \u{25B8} **Location**.",
                "**The target is below the horizon**. The Aim readout says **Below the horizon** and when the target rises.",
                "**Sensor problem**. Close Lodestar and open it again. Aiming needs a real iPhone, because the Simulator has no motion sensors.",
                "**Part of the screen is not red at night**. Lodestar cannot tint the rest of iOS. Set up **Color Filters**, as explained in **Night mode**.",
                "**The last update failed.** Lodestar keeps the data you already have. Wait, then tap **Update now** in **Settings** \u{25B8} **Online Data**.",
                "**Still stuck?** Read the support page at https://feetball.github.io/Lodestar/support.html, or report the problem on the issue tracker at https://github.com/feetball/Lodestar/issues.",
            ]),
        ],
        related: [.alignment, .compassAndGyro, .mounting])

    private static let glossary = HelpTopic(
        topic: .glossary, category: .more, title: "Glossary", systemImage: "character.book.closed",
        summary: "Plain meanings of the astronomy words used in Lodestar.",
        keywords: ["terms", "words", "meaning", "definitions", "jargon", "magnitude", "declination", "twilight"],
        blocks: [
            .paragraph("These are the words Lodestar uses, in alphabetical order. Angles are in degrees (\u{00B0}), and a full circle is 360\u{00B0}."),
            .terms([
                HelpTerm(term: "Altitude", meaning: "How high an object is above the horizon, in degrees. 0\u{00B0} is the horizon and 90\u{00B0} is straight up."),
                HelpTerm(term: "Azimuth", meaning: "The compass direction of an object, in degrees clockwise from north. East is 90\u{00B0}, south 180\u{00B0} and west 270\u{00B0}."),
                HelpTerm(term: "Conjunction", meaning: "Two objects that look close together in the sky, such as a planet and the Moon."),
                HelpTerm(term: "Declination", meaning: "The sky\u{2019}s latitude, in degrees north (+) or south (\u{2212}) of the celestial equator."),
                HelpTerm(term: "Elongation", meaning: "How far a planet or comet is from the Sun in the sky. A small elongation means it is lost in the Sun\u{2019}s glare."),
                HelpTerm(term: "Field of view", meaning: "How much sky your camera\u{2019}s picture covers, worked out from the sensor and the focal length. It is written as width \u{00D7} height in degrees."),
                HelpTerm(term: "Greatest elongation", meaning: "The moment Mercury or Venus is farthest from the Sun in the sky. It is the best time to see it."),
                HelpTerm(term: "Gyro Lock", meaning: "A heading from the gyroscope instead of the compass, so tripod heads and camera bodies can no longer disturb it. It drifts slowly. See Compass, Gyro Lock and accuracy."),
                HelpTerm(term: "Magnitude", meaning: "How bright an object is. The lower the number, the brighter it is, and negative numbers are very bright. The faintest stars seen with the eye are about magnitude 6."),
                HelpTerm(term: "NPF rule and 500 rule", meaning: "Rules of thumb for the longest exposure before stars start to trail. The NPF rule also takes the aperture and the pixel size into account. The 500 rule is optimistic for high-resolution sensors."),
                HelpTerm(term: "Opposition", meaning: "When a planet is opposite the Sun in the sky. It is then at its brightest and up all night."),
                HelpTerm(term: "Pan and tilt", meaning: "Pan turns a tripod head sideways. Tilt turns it up or down."),
                HelpTerm(term: "Position angle (PA)", meaning: "How the camera\u{2019}s frame is turned on the sky, measured from celestial north toward east. See Plan your framing."),
                HelpTerm(term: "Radiant", meaning: "The point in the sky that the meteors of a shower seem to come from."),
                HelpTerm(term: "Residual (RMS)", meaning: "How far the points of your star alignment disagree after the fit. Smaller is better. Settings shows it as **Fit residual (RMS)**."),
                HelpTerm(term: "Right ascension (RA)", meaning: "The sky\u{2019}s longitude, counted eastward in hours (or degrees) from a fixed point among the stars."),
                HelpTerm(term: "Roll", meaning: "How far the camera or frame is tilted sideways against the horizon. 0\u{00B0} is level."),
                HelpTerm(term: "Twilight", meaning: "The glow before sunrise and after sunset, in three stages by how far the Sun is below the horizon. Civil: up to 6\u{00B0}. Nautical: 6\u{00B0} to 12\u{00B0}. Astronomical: 12\u{00B0} to 18\u{00B0}. Beyond that the sky is fully dark."),
                HelpTerm(term: "Zenith", meaning: "The point straight overhead."),
                HelpTerm(term: "ZHR (zenithal hourly rate)", meaning: "The number of meteors an observer would count per hour under a perfectly dark sky with the radiant straight overhead. Real counts are lower."),
            ]),
        ],
        related: [.planFraming, .alignment])

    /// The topics of "Equipment" and "More".
    static let more: [HelpTopic] = [mounts, nightMode, onlineData, widgets, troubleshooting, glossary]
}
