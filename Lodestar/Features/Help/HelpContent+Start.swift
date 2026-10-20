import Foundation

extension HelpContent {
    private static let gettingStarted = HelpTopic(
        topic: .gettingStarted, category: .start, title: "Your first night", systemImage: "flag",
        summary: "Five steps from a fresh install to your first target.",
        keywords: ["getting", "started", "setup", "tutorial", "beginner", "basics", "begin", "walkthrough", "quick"],
        blocks: [
            .paragraph("Lodestar turns an iPhone clamped to your camera into a finder for the night sky. Do the first three steps once. After that, each night you only align and pick a target."),
            .steps([
                "**Mount the phone.** Clamp it firmly to the camera, then choose how it sits in **Settings** \u{25B8} **Mount**.",
                "**Enter your camera and lens** in **Settings** \u{25B8} **Camera & Lens**. Lodestar draws the outline of your frame from them, and the exposure tools use them to work out the longest exposure before stars trail.",
                "**Set where you are.** Allow location access (approximate is fine) or choose a site in **Settings** \u{25B8} **Location**. **Add Site\u{2026}** lets you pick a place on the map or type coordinates.",
                "**Align on a star.** On the Aim tab, tap **Align** and choose a bright star or planet. Center it in your camera\u{2019}s viewfinder or live view, then tap **Centered \u{2014} Sync**.",
                "**Pick a target and follow the arrow.** Tap **Target** and choose something from **Quick picks**, or search. Turn the tripod head the way the arrow points. When the screen says **In your frame** with a check mark, fine-tune in your camera\u{2019}s live view.",
            ]),
            .tip("You can try it at home. Turn the **Camera** button off and the Aim screen shows a virtual sky, drawn from the phone\u{2019}s sensors, that moves as you move the phone."),
        ],
        related: [.mounting, .alignment, .aimScreen, .troubleshooting])

    private static let mounting = HelpTopic(
        topic: .mounting, category: .start, title: "Mounting the phone", systemImage: "iphone",
        summary: "Clamp the phone firmly and pick the matching mount.",
        keywords: ["clamp", "bracket", "orientation", "portrait", "landscape", "upside", "flat", "preset", "tripod", "rig"],
        blocks: [
            .paragraph("Lodestar works out where your camera points from how the phone is turned. That only works if the phone cannot move on the camera, and if Lodestar knows how it sits."),
            .bullets([
                "Use a rigid bracket. Any wobble in the clamp shows up as aiming error.",
                "Choose the mount in **Settings** \u{25B8} **Mount**. The first row opens a list with a picture for each preset.",
                "The four **Back camera** presets are for a phone with its rear camera looking along the lens: **portrait** (upright), **upside down**, and **landscape** with the top edge to your left or to your right.",
                "The two **Flat on top** presets are for a phone lying screen up on top of the camera, with its top edge pointing along the lens (**top edge forward**) or toward you (**top edge back**). The phone\u{2019}s own camera then sees the ground, so the **Camera** button is not available.",
                "Line the phone up with the lens as closely as you can. Star alignment corrects small tilts.",
            ]),
            .tip("Not sure which preset fits? Compare the pictures with your rig. Each one marks the phone\u{2019}s top edge."),
            .caution("Changing the mount or the heading source clears your star alignment. After you remount the phone, align again."),
        ],
        related: [.alignment, .compassAndGyro, .gettingStarted])

    private static let aimScreen = HelpTopic(
        topic: .aimScreen, category: .aiming, title: "The Aim screen", systemImage: "scope",
        summary: "What the Aim screen shows and what its buttons do.",
        keywords: ["arrow", "guidance", "chips", "status", "icons", "hud", "roll", "crosshair", "readout", "buttons"],
        blocks: [
            .paragraph("The Aim tab is your screen at the tripod. It shows the sky where your camera points and leads you to the target."),
            .bullets([
                "**Camera** switches your camera\u{2019}s picture behind the sky on and off. Pinch to zoom, or tap the zoom button to step through 100\u{00B0}, 60\u{00B0}, 40\u{00B0} and 20\u{00B0} of virtual sky, or 1\u{00D7}, 2\u{00D7}, 4\u{00D7} and 8\u{00D7} of picture.",
                "**The arrow** circles the middle of the screen and points the shortest way to the target, with the distance left in degrees. The rectangle outlines your camera\u{2019}s frame.",
                "**The card** shows the target\u{2019}s name, kind, altitude (**Alt**, height) and azimuth (**Az**, compass direction). Two readouts such as **Pan right 30.7\u{00B0}** and **Tilt up 12.4\u{00B0}** say how far to turn each axis.",
                "**On target**, a ring with a check mark replaces the arrow and the panel reads **In your frame \u{00B7} 8.2\u{00B0} from center**. Haptics tap when you arrive and leave. Optional audio ticks are in **Settings** \u{25B8} **Feedback**.",
                "**Chips**, the small labels along the top: **Compass good**, **Compass fair** or **Compass poor** (or **Gyro lock**), **Magnetic interference**, **Not aligned** or **Aligned \u{00B1}0.6\u{00B0} \u{00B7} 2 pts**, **Virtual sky**, **Approx. location**, camera notices and Starlink streak warnings.",
                "**The level gauge**, top right, reads **Level** with a check mark when the camera is level.",
                "**Buttons:** **Target**, **Align**, **Mosaic**, **Camera**, the night button (**Night off**, **Night on** or **Night auto**) and zoom. **Mount** appears once a GoTo mount has connected.",
                "**No target?** A panel names the planet, bright star or deep-sky object closest to the middle of the picture, within a few degrees. **Aim here** makes it your target; **Choose target** opens the list. The circled \u{00D7} on the card clears the target.",
            ]),
        ],
        related: [.alignment, .compassAndGyro, .mounts, .troubleshooting])

    private static let alignment = HelpTopic(
        topic: .alignment, category: .aiming, title: "Star alignment", systemImage: "dot.viewfinder",
        summary: "Teach Lodestar where north is and how the phone sits.",
        keywords: ["sync", "calibrate", "calibration", "accuracy", "reference", "heading", "bracket", "reset", "centered", "error"],
        blocks: [
            .paragraph("Phone compasses can be off by several degrees near camera bodies and metal. Aligning teaches Lodestar which way north really is for your phone and how the phone sits on the camera. One star corrects the heading; stars at different heights in the sky also correct the tilt of your bracket."),
            .steps([
                "On the Aim tab, tap **Align**.",
                "Choose a bright star or planet. The list shows objects between 15\u{00B0} and 78\u{00B0} above the horizon, nearest to where your camera points first.",
                "The object becomes your target, so the arrows lead you to it. Steer the tripod until it is centered in your camera\u{2019}s frame, in the viewfinder or live view.",
                "Tap **Centered \u{2014} Sync**.",
                "For much better accuracy, repeat with a second object in another part of the sky, at a different height. Tap **Done** when you finish.",
            ]),
            .bullets([
                "The chip at the top then reads, for example, **Aligned \u{00B1}0.6\u{00B0} \u{00B7} 2 pts**: the expected pointing error and the number of stars synced. Aim for \u{00B1}1\u{00B0} or better. After one star it is large (over \u{00B1}10\u{00B0}), because one star cannot tell a compass error from a tilted bracket.",
                "In the panel, a minus button removes one point and **Reset alignment** starts over. **Settings** \u{25B8} **Mount** also has **Reset Alignment** and shows the corrections.",
                "With a GoTo mount connected, a switch in the panel can also sync the mount to the star.",
            ]),
            .tip("Align on a star near your target, then add a second star far from the first."),
            .caution("Align again after you remount the phone, change the mount or heading source, or restart the app, or if the arrows seem off."),
        ],
        related: [.compassAndGyro, .mounting, .troubleshooting])

    private static let compassAndGyro = HelpTopic(
        topic: .compassAndGyro, category: .aiming, title: "Compass, Gyro Lock and accuracy", systemImage: "safari",
        summary: "What the compass chips mean and how to steady them.",
        keywords: ["heading", "north", "magnetic", "interference", "gyroscope", "declination", "drift", "diagnostics", "sensors", "wmm"],
        blocks: [
            .paragraph("Lodestar finds where the camera points from the phone\u{2019}s compass and gyroscope. A compass is typically good to a few degrees, and tripod heads, camera bodies, lens motors and even a magnetic case can disturb it."),
            .bullets([
                "The chip at the top says **Compass good**, **Compass fair** or **Compass poor**. **Magnetic interference** appears when the magnetic field the phone measures differs a lot from what it should be at your place.",
                "Two things help: align on a star, or use Gyro Lock.",
                "Set **Heading source** to **Gyro Lock** in **Settings** \u{25B8} **Mount**. It copies the compass heading to the gyroscope once the phone holds still, then ignores the compass, so tripod heads and camera bodies can no longer disturb it. Hold the phone steady for a moment after opening the Aim screen. The heading drifts slowly, so align on a star again if it does.",
                "The chip **Set heading: align on a star** means Gyro Lock has no heading yet. One alignment sets it.",
                "Lodestar turns the compass reading into true north with the World Magnetic Model, so it works without Location Services.",
                "With two or more stars at different heights, expect to land within about a degree, inside the frame of all but long telephoto lenses.",
                "**Settings** \u{25B8} **About** \u{25B8} **Sensor Diagnostics** checks the sensors. With the phone upright and the camera facing north, the gravity check should read PASS.",
            ]),
            .tip("A phone case with a magnetic clasp can throw the compass off. If the chip says **Compass poor**, try the phone without its case, as far from metal as the bracket allows."),
            .caution("Changing the heading source clears your star alignment."),
        ],
        related: [.alignment, .mounting, .troubleshooting])

    /// The topics of "Get started" and "Aiming".
    static let start: [HelpTopic] = [gettingStarted, mounting, aimScreen, alignment, compassAndGyro]
}
