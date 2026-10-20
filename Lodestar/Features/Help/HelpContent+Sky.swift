import Foundation

extension HelpContent {
    // MARK: Sky and objects

    private static let objects = HelpTopic(
        topic: .objects, category: .sky, title: "Finding objects", systemImage: "sparkles",
        summary: "Search, browse and favorite planets, nebulae and stars.",
        keywords: ["search", "catalog", "messier", "ngc", "m31", "favorites", "custom target", "sort", "filter", "comets"],
        blocks: [
            .paragraph("The **Objects** tab is the catalog of what Lodestar can aim at, from planets to faint nebulae. Find a target here, then send it to the Aim screen."),
            .bullets([
                "**Search** by name or number, such as M31, NGC 7000, Sh2-155 or HIP 32349. Greek letters work spelled out or not: alpha CMa or \u{03B1} CMa.",
                "**Browse** by group: Solar System, Stars, Galaxies, Nebulae, Star Clusters and Special (the Milky Way core and the celestial poles). Asteroids, and comets if you switch them on in **Settings** \u{25B8} **Online Data**, are under Solar System.",
                "**Chips** above the list limit it to one catalog, such as Messier. **The menu** at the top right sorts by name, brightness, altitude or rise time, and filters with **Above Horizon Now**, **Hide Faint** and **Popular Only**.",
                "**Swipe** a row right to favorite it, or left to aim at it. Favorites and recents are listed first. The **+** button adds a custom target from a right ascension and declination, the sky\u{2019}s coordinates.",
                "**Tap a row** for the object\u{2019}s page: where it is now, when it rises, reaches its highest point and sets, an altitude chart for the night, how much of your camera frame it fills, and the longest exposure before stars trail. A comet shows which way its tail points. **Aim at \u{2026}** sends the object to the Aim screen. A row for an object below the horizon says when it rises.",
            ]),
            .caution("The Sun is listed under Solar System. Never point a camera at it without a certified solar filter."),
        ],
        related: [.skyChart, .aimScreen, .tonight])

    private static let skyChart = HelpTopic(
        topic: .skyChart, category: .sky, title: "The sky chart", systemImage: "circle.dotted.circle",
        summary: "Your whole sky at any hour, with a time bar.",
        keywords: ["sky tab", "planisphere", "star map", "planetarium", "zenith", "layers", "constellations", "time travel", "camera view", "zoom"],
        blocks: [
            .paragraph("The **Sky** tab draws the whole sky above you as a round chart. The point straight overhead, the zenith, is in the middle, and the horizon is the outer circle. North is at the top and east is on the left, as when you lie on your back and look up."),
            .bullets([
                "**Pinch** to zoom, up to 15\u{00D7}, and drag to move. Tap an object to open its card, with **Aim** and **Details**. The magnifier button in the top bar resets the zoom.",
                "**The time bar** at the bottom moves the chart to any moment within a year of now. Slide it, tap **\u{2212}1h** or **+1h**, or use the calendar button to jump by days. **Now** brings you back.",
                "**The layers button** (top right) turns on or off the constellation lines and names, the Milky Way, deep-sky objects (galaxies, nebulae and clusters), star names, an altitude grid, **Camera view** and **Frame in the middle**. **Faintest star** sets how faint the stars can be.",
                "**Camera view** shows where your phone points: a crosshair and the outline of your camera\u{2019}s frame. The top of the screen gives its azimuth (compass direction) and altitude (height above the horizon). A camera pointing below the horizon shows as an arrow on the horizon circle.",
                "**The compass button** in the top bar turns the chart so the way your camera faces is at the top (**Heading up**).",
                "If you have recorded your skyline, the ground below it is shaded.",
            ]),
            .tip("Slide the time bar ahead to see where a target will be when you start shooting."),
        ],
        related: [.planFraming, .objects, .tonight])

    private static let tonight = HelpTopic(
        topic: .tonight, category: .sky, title: "Tonight", systemImage: "moon.stars",
        summary: "When it is dark, where the Moon is, what to shoot.",
        keywords: ["twilight", "darkness", "moon phase", "milky way", "planets", "best targets", "sunset", "sunrise", "clouds", "forecast"],
        blocks: [
            .paragraph("The **Tonight** tab shows what the night will be like where you are: when it gets dark, when the Moon is up, and what is worth shooting. Use it to plan before you set up."),
            .bullets([
                "**Darkness** is a timeline of the night with a **Now** marker. Its bars show the sky\u{2019}s brightness, when the Moon is up, the dark hours without the Moon, and when the Milky Way core can be photographed.",
                "**Sun & Twilight** lists sunset, dusk, dawn and sunrise. The sky is fully dark when the Sun is more than 18\u{00B0} below the horizon.",
                "**Moon** gives the phase, moonrise, moonset and the dark hours you get without it. **Milky Way Core** and **Planets** say when they are high enough to shoot.",
                "**Best Targets** ranks deep-sky objects by height in the dark, brightness and size. **Upcoming** lists the next sky events. **Polar Alignment** is a clock for aligning a star tracker.",
                "To see another night, use the arrows at the top or tap the date. You can go a year either way. **Tonight** brings you back.",
                "With a recorded skyline, the times follow it. If you switch on **Cloud forecast** in **Settings** \u{25B8} **Online Data**, a **Clouds tonight** card appears.",
            ]),
            .tip("Long stretches in the **Dark sky** bar are your best hours for faint objects."),
        ],
        related: [.events, .skyline, .nightMode])

    private static let events = HelpTopic(
        topic: .events, category: .sky, title: "Events calendar", systemImage: "calendar",
        summary: "Meteor showers, eclipses, conjunctions and more.",
        keywords: ["meteor shower", "eclipse", "conjunction", "opposition", "elongation", "supermoon", "equinox", "solstice", "zhr", "radiant"],
        blocks: [
            .paragraph("The events calendar lists what the sky has coming in the next twelve months, with times for your site, so you can plan ahead."),
            .bullets([
                "It covers meteor showers, lunar and solar eclipses, conjunctions (two bodies close together), oppositions (a planet opposite the Sun), greatest elongations (Mercury or Venus farthest from the Sun), supermoons, equinoxes and solstices.",
                "A meteor shower shows its hourly rate (ZHR) and how high its radiant is, the point the meteors seem to come from. ZHR is for a perfectly dark sky with the radiant overhead, so real counts are lower.",
            ]),
            .steps([
                "On the **Tonight** tab, find the **Upcoming** card and tap **Calendar**.",
                "Tap a chip such as **Meteor Showers** or **Eclipses** to narrow the list. **Visible from here only** hides what you cannot see from your site.",
                "Tap an event for when and where to look and how to photograph it. The **Aim at \u{2026}** buttons send it to the Aim screen. **Show in Sky chart** opens the Sky tab at the time of the event.",
            ]),
            .tip("For a meteor shower, aim about 40\u{00B0} away from the radiant, not at it. Meteors then draw long trails across the frame."),
            .caution("Never point a camera at the Sun without a certified solar filter. On a solar eclipse page, Lodestar asks you to confirm the filter before it aims at the Sun."),
        ],
        related: [.tonight, .skyChart])

    // MARK: Planning a picture

    private static let planFraming = HelpTopic(
        topic: .planFraming, category: .planning, title: "Plan your framing", systemImage: "camera.viewfinder",
        summary: "Place your camera frame on the sky chart.",
        keywords: ["composition", "field of view", "camera view", "frame in the middle", "rotate", "portrait", "level", "position angle", "roll", "lens"],
        blocks: [
            .paragraph("Check how a target will sit in your picture before you set up. The Sky tab can hold your camera\u{2019}s frame in the middle while you move the sky under it."),
            .steps([
                "Enter your camera and lens in **Settings** \u{25B8} **Camera & Lens**. The frame is drawn from them.",
                "On the **Sky** tab, open the layers menu. Turn on **Camera view**, then **Frame in the middle**.",
                "Drag to move the frame over the sky and pinch to zoom, up to 15\u{00D7}. Zoomed in, large objects are drawn near their real size. The frame stays on the same stars as time passes, so use the time bar to see how it will look later.",
                "Turn the frame by twisting two fingers, or press and hold on the chart, then drag around the middle. It snaps at 0\u{00B0}, 90\u{00B0}, 180\u{00B0} and 270\u{00B0}. The **90\u{00B0}** button gives a quarter turn, for a portrait frame.",
                "Tap **Aim here** to open the Aim screen, guided to the middle of the frame. There, the frame follows how you turn the phone, as your camera does on the tripod.",
            ]),
            .bullets([
                "The panel under the chart shows your lens and its field of view (for example 24 mm \u{00B7} 74\u{00B0} \u{00D7} 53\u{00B0}), the frame\u{2019}s position in the sky, and **Below the horizon** when it is.",
                "**PA** (position angle) is how the picture\u{2019}s top edge is turned, measured from celestial north toward east. It stays the same as the sky turns, as it does for a camera on a star tracker.",
                "**roll** is the frame\u{2019}s tilt against the horizon. 0\u{00B0} is level, which a camera on a plain tripod needs. **Level** turns the frame level here and now. The roll changes through the night, but PA does not.",
            ]),
            .caution("The frame is drawn from your camera and lens in Settings. If those are wrong, so is the frame. Below the horizon, only the part above it is drawn."),
        ],
        related: [.skyChart, .aimScreen, .glossary])

    private static let mosaic = HelpTopic(
        topic: .mosaic, category: .planning, title: "Mosaic planner", systemImage: "square.grid.3x3",
        summary: "Cover a wide area with a grid of overlapping shots.",
        keywords: ["panorama", "panels", "grid", "overlap", "stitch", "milky way arch", "wide field", "big nebula"],
        blocks: [
            .paragraph("Some targets are bigger than one frame, and the Milky Way arch spans the sky. A mosaic covers the area with a grid of overlapping panels, which you stitch together later. Lodestar plans the grid and guides you to each panel."),
            .steps([
                "On the **Aim** screen, tap **Mosaic**.",
                "Under **Cover**, choose **Fit target** (the Aim target, with a margin), **Milky Way arch panorama** or **Custom size**. For a custom size, set the width and height. **Use where the camera points now** centers it.",
                "Under **Shots**, set the **Overlap** and how you hold the camera: **Landscape** or **Portrait**. Lodestar suggests the one that needs fewer panels. The lens comes from Settings.",
                "Check the **Plan** card for the rows, columns, panel count and any warnings. Then tap **Start**.",
                "Lodestar steers you to each panel in turn and tells you how far to rotate the camera. The screen shows progress, such as Panel 3 of 12. Take the shot, then tap **Shot taken \u{2192} Next**. The panels also appear on the sky chart.",
                "Tap **Finish** to end the mosaic.",
            ]),
            .tip("An object\u{2019}s page tells you when it needs a mosaic with your lens."),
            .caution("A mosaic cannot follow the Sun, Moon, planets, comets or asteroids, because they move against the stars."),
        ],
        related: [.planFraming, .aimScreen])

    private static let trailsAndExposure = HelpTopic(
        topic: .trailsAndExposure, category: .planning, title: "Exposure, star trails and time-lapse", systemImage: "timer",
        summary: "Longest exposure, star trail and time-lapse planners.",
        keywords: ["exposure calculator", "npf", "500 rule", "star trails", "timelapse", "interval", "stacking", "shutter", "trailing", "tools"],
        blocks: [
            .paragraph("Stars drift across the sky, so a long exposure turns them into streaks. These tools help you pick an exposure that keeps stars sharp, or plan star trails and time-lapses on purpose."),
            .bullets([
                "Open them in **Settings** \u{25B8} **Tools**: **Exposure Calculator**, **Star Trails & Time-Lapse** and **Polar Alignment**.",
                "The **Exposure Calculator** gives the longest exposure before stars trail. The NPF rule counts your aperture and pixel size, so it suits high-resolution sensors. The 500 rule is simpler but too generous for them.",
                "**Star Trails & Time-Lapse** plans how long to shoot for a trail, how to stack short frames, and how many pictures, how much time and how much storage a time-lapse needs.",
                "**Polar Alignment** shows where the pole star stands against the celestial pole, as a clock position. It helps you aim a star tracker\u{2019}s axis at the pole. The **Tonight** tab has the same clock.",
                "The planners start from your camera in Settings. Changes you make in a planner stay in that planner.",
                "Each object\u{2019}s page also shows the longest exposure before stars trail.",
            ]),
            .tip("Stars near the celestial pole move more slowly, so you can expose longer when you aim toward it."),
            .caution("These limits are rules of thumb. Check the stars in your first test frame at full size."),
        ],
        related: [.objects, .glossary])

    private static let skyline = HelpTopic(
        topic: .skyline, category: .planning, title: "Record your skyline", systemImage: "mountain.2",
        summary: "Teach Lodestar where trees and hills hide the sky.",
        keywords: ["horizon", "trees", "buildings", "hills", "mountains", "obstructions", "sweep", "saved site", "rise and set"],
        blocks: [
            .paragraph("Trees, buildings and hills hide objects long before the true horizon. Record your site\u{2019}s real skyline once. Rise and set times, Tonight, the object pages and the sky chart then use it, and the Aim screen shades the ground below it."),
            .steps([
                "Go to your site and choose it in **Settings** \u{25B8} **Location**. A skyline belongs to a saved site, so for **Current Location** Lodestar offers to save it as a site first.",
                "Tap the mountain button on the site, or edit the site and open its **Horizon** section. Choose **Record Skyline\u{2026}**, or **Clear Skyline\u{2026}** to remove one.",
                "Hold the phone so its back camera points at the skyline, with the line on the crosshair. Turn slowly all the way round. Sweep back over a stretch to redo it.",
                "The screen shows how much is covered and what is still to sweep. **Start Over** begins again.",
                "Tap **Done** to save. If the circle is not complete, Lodestar asks what to do with the gaps.",
            ]),
            .tip("Record in daylight, when the camera picture shows the skyline. It helps you keep the line on the crosshair."),
            .caution("A skyline belongs to one spot. If you move a site by more than about 100 m, record it again."),
        ],
        related: [.tonight, .objects])

    /// The topics of "Sky and objects" and "Planning a picture".
    static let sky: [HelpTopic] = [objects, skyChart, tonight, events, planFraming, mosaic, trailsAndExposure, skyline]
}
