import Foundation

extension HelpContent {
    // MARK: Sky and objects

    private static let objects = HelpTopic(
        topic: .objects, category: .sky, title: "Finding objects", systemImage: "sparkles",
        summary: "Search, browse and favorite planets, nebulae and stars.",
        keywords: ["search", "catalog", "messier", "ngc", "m31", "favorites", "custom target", "sort", "filter", "comets", "hour angle", "meridian", "transit", "moon", "moonlight", "narrowband", "light pollution"],
        blocks: [
            .paragraph("The **Objects** tab is the catalog of what Lodestar can aim at, from planets to faint nebulae. Find a target here, then send it to the Aim screen."),
            .bullets([
                "**Search** by name or number, such as M31, NGC 7000, Sh2-155 or HIP 32349. Greek letters work spelled out or not: alpha CMa or \u{03B1} CMa.",
                "**Browse** by group: Solar System, Stars, Galaxies, Nebulae, Star Clusters and Special (the Milky Way core and the celestial poles). Asteroids, and comets if you switch them on in **Settings** \u{25B8} **Online Data**, are under Solar System.",
                "**Chips** above the list limit it to one catalog, such as Messier. **The menu** at the top right sorts by name, brightness, altitude, rise time or **Hours Visible Tonight**, and filters with **Above Horizon Now**, **Visible \u{2265} 1 h Tonight**, **Hide Faint** and **Popular Only**. The hours count the dark time an object is above your recorded skyline (a flat horizon without one) and at least 20\u{00B0} high, and each row then ends with \u{201C}3.4 h tonight\u{201D} or, for an object your skyline hides all night, \u{201C}behind skyline\u{201D}.",
                "**Imaged Only** in the menu keeps the objects you logged as imaged, and a check mark on a row shows them. **Import List\u{2026}** reads a CSV table, a Telescopius export or a SkySafari observing list, finds its objects in the catalog by name or number and adds them to your favorites. **Export Favorites\u{2026}** saves them as a table or a SkySafari list.",
                "**Swipe** a row right to favorite it, or left to aim at it. Favorites and recents are listed first. The **+** button adds a custom target from a right ascension and declination, the sky\u{2019}s coordinates.",
                "**Tap a row** for the object\u{2019}s page. It shows where the object is now, with its hour angle (negative east of the meridian, the line from north to south across the sky, and positive west of it) and when it crosses that line. It also shows when the object rises, reaches its highest point and sets, with an altitude chart. With a recorded skyline, **Above your skyline** gives the hours tonight it is clear of it. Then come how much of your camera frame the object fills and the longest exposure before stars trail. A comet shows which way its tail points. **Aim at \u{2026}** sends the object to the Aim screen. A row for an object below the horizon says when it rises.",
                "**The Moon line** on the page says how much moonlight will matter for the object: its distance from the Moon and the Moon\u{2019}s lit part give **minor**, **moderate** or **severe**. If you choose a light-pollution or narrowband **Filter** in **Settings** \u{25B8} **Camera & Lens**, emission nebulae, planetary nebulae and supernova remnants are judged more leniently, and the line says so, for example **Moderate \u{00B7} fine with your narrowband filter**. Galaxies, reflection nebulae, clusters and stars shine in all colors, so a filter does not help them.",
            ]),
            .caution("The Sun is listed under Solar System. Never point a camera at it without a certified solar filter."),
        ],
        related: [.skyChart, .aimScreen, .tonight])

    private static let skyChart = HelpTopic(
        topic: .skyChart, category: .sky, title: "The sky chart", systemImage: "circle.dotted.circle",
        summary: "Your whole sky at any hour, with a time bar.",
        keywords: ["planisphere", "star map", "planetarium", "zenith", "overhead", "layers", "constellations", "time travel", "camera view", "zoom"],
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
        keywords: ["twilight", "darkness", "moon phase", "milky way", "planets", "best targets", "sunset", "sunrise", "clouds", "forecast", "sky quality", "bortle", "light pollution", "imaging score", "darkest sky"],
        blocks: [
            .paragraph("The **Tonight** tab shows what the night will be like where you are: when it gets dark, when the Moon is up, and what is worth shooting. Use it to plan before you set up."),
            .bullets([
                "**Darkness** is a timeline of the night with a **Now** marker. Its bars show the sky\u{2019}s brightness, when the Moon is up, the dark hours without the Moon, and when the Milky Way core can be photographed.",
                "**Sun & Twilight** lists sunset, dusk, dawn and sunrise. The sky is fully dark when the Sun is more than 18\u{00B0} below the horizon.",
                "**Moon** gives the phase, moonrise, moonset and the dark hours you get without it. **Milky Way Core** and **Planets** say when they are high enough to shoot.",
                "**Sky quality** estimates how dark the sky is at the site as a Bortle class (1 is a pristine dark sky, 9 an inner-city sky) from satellite night-light imagery, says toward which compass direction the sky is darker, and scores the night for imaging out of 10: dark hours, the Moon, the sky\u{2019}s brightness and, when the cloud forecast is on and up to date, clouds. The estimate and its limits are explained in **Observing sites**.",
                "**Best Targets** ranks deep-sky objects (galaxies, nebulae and clusters) by height in the dark, brightness and size, and moves down those that the Moon spoils. Each row says what the Moon does to it at its best time, and your **Filter** setting counts. With a recorded skyline each row says how many hours the object is clear of it, and targets that stay clear for longer rank higher. **Upcoming** lists the next sky events. **Polar Alignment** is a clock for aligning a star tracker.",
                "To see another night, use the arrows at the top or tap the date. You can go a year either way. **Tonight** brings you back.",
                "With a recorded skyline, the times follow it. If you switch on **Cloud forecast** in **Settings** \u{25B8} **Online Data**, a **Clouds tonight** card appears.",
                "Under the cloud strip, **Clouds tonight** shows chips for **Dew**, **Wind**, **Fog** and the night\u{2019}s temperature range, one line for the most important warning, and an **Hourly** table of cloud, temperature, dew gap and wind. **Dew** appears when the air gets within 2\u{00A0}\u{00B0}C of its dew point, when dew can form on your lens: bring a dew heater or shield. **Wind** warns from 5\u{00A0}m/s (11\u{00A0}mph) that long exposures may shake, from 8\u{00A0}m/s (18\u{00A0}mph) that the tripod needs weight, and from 12\u{00A0}m/s (27\u{00A0}mph) that the wind is strong. **Fog** appears when the forecast puts fog over at least half the area around you. Temperatures and speeds follow your region: \u{00B0}C and m/s, or \u{00B0}F and mph.",
            ]),
            .tip("Long stretches in the **Dark sky** bar are your best hours for faint objects."),
        ],
        related: [.sites, .events, .skyline, .nightMode])

    private static let events = HelpTopic(
        topic: .events, category: .sky, title: "Events calendar", systemImage: "calendar",
        summary: "Meteor showers, eclipses, conjunctions and more.",
        keywords: ["meteor shower", "eclipse", "conjunction", "opposition", "elongation", "supermoon", "equinox", "solstice", "zhr", "radiant", "meteor camera", "where to point", "meteors per hour", "iss transit", "transit", "centreline", "silhouette"],
        blocks: [
            .paragraph("The events calendar lists what the sky has coming in the next twelve months, with times for your site, so you can plan ahead."),
            .bullets([
                "It covers meteor showers, lunar and solar eclipses, conjunctions (two bodies close together), oppositions (a planet opposite the Sun), greatest elongations (Mercury or Venus farthest from the Sun), supermoons, equinoxes and solstices.",
                "A meteor shower shows its hourly rate (ZHR) and how high its radiant is, the point the meteors seem to come from. ZHR is for a perfectly dark sky with the radiant overhead, so real counts are lower.",
                "A meteor shower also has a **Camera** card. It says where to point the camera, high in the dark sky about 40\u{00B0} from the radiant and away from the Moon, and about how many meteors to expect in the frame of your lens from **Settings** \u{25B8} **Camera & Lens**. It is worked out for the time of the night when the radiant is highest. **Aim camera there** makes that place a target and opens the Aim screen; **Aim at the radiant** stays in the actions at the top.",
            ]),
            .steps([
                "On the **Tonight** tab, find the **Upcoming** card and tap **Calendar**.",
                "Tap a chip such as **Meteor Showers** or **Eclipses** to narrow the list. **Visible from here only** hides what you cannot see from your site.",
                "Tap an event for when and where to look and how to photograph it. The **Aim at \u{2026}** buttons send it to the Aim screen. **Show in Sky chart** opens the Sky tab at the time of the event.",
            ]),
            .paragraph("**ISS transits of the Sun and Moon** sit at the top of the calendar when **Satellite passes** is on in **Settings** \u{25B8} **Online Data** and the orbit data is fresh. The card lists, for the next 14 days, when the ISS or Tiangong crosses the Sun or the Moon, either as seen from your site (**from here**) or from a place within 50 km, the **centreline**, where the satellite crosses the middle of the disc. Tap one for the time to the second, the height and direction of the Sun or Moon, how long the crossing lasts (often under a second), the satellite\u{2019}s size and distance, and the centreline\u{2019}s distance, direction and coordinates, which **Copy coordinates** puts on the clipboard. **Aim at the Moon** or **Aim at the Sun** opens the Aim screen."),
            .tip("For a meteor shower, aim about 40\u{00B0} away from the radiant, not at it. Meteors then draw long trails across the frame. Use your widest lens, the NPF exposure and continuous shooting, and keep the radiant in or near the edge of the frame."),
            .tip("For a transit, use burst mode at 1/2000 s or faster and start a few seconds early. The orbit changes from day to day, so update the orbit data and check the time again on the day."),
            .caution("Never point a camera at the Sun without a certified solar filter. On a solar eclipse page or a Sun transit, Lodestar asks you to confirm the filter before it aims at the Sun."),
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
                "Enter your camera and lens in **Settings** \u{25B8} **Camera & Lens**. The frame is drawn from the profile in use. A fisheye lens gets a curved frame.",
                "On the **Sky** tab, open the layers menu. Turn on **Camera view**, then **Frame in the middle**.",
                "Drag to move the frame over the sky and pinch to zoom, up to 15\u{00D7}. Zoomed in, large deep-sky objects are drawn near their real size. The frame stays on the same stars as time passes, so use the time bar to see how it will look later.",
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
        related: [.skyChart, .aimScreen, .cameraAndLens, .glossary])

    private static let mosaic = HelpTopic(
        topic: .mosaic, category: .planning, title: "Mosaic planner", systemImage: "square.grid.3x3",
        summary: "Cover a wide area with a grid of overlapping shots.",
        keywords: ["panorama", "panels", "grid", "overlap", "stitch", "milky way arch", "wide field", "big nebula"],
        blocks: [
            .paragraph("Some targets are bigger than one frame, and the Milky Way arch spans the sky. A mosaic covers the area with a grid of overlapping panels, which you stitch together later. Lodestar plans the grid and guides you to each panel."),
            .steps([
                "On the **Aim** screen, tap **Mosaic**.",
                "Under **Cover**, choose **Fit target** (the Aim target, with a margin), **Milky Way arch panorama** or **Custom size**. For a custom size, set the width and height. **Use where the camera points now** centers it.",
                "Under **Shots**, set the **Overlap**, how much neighboring panels share, and how you hold the camera: **Landscape** or **Portrait**. Lodestar suggests the one that needs fewer panels. The lens comes from Settings.",
                "Check the **Plan** card for the rows, columns, panel count and any warnings. Then tap **Start**.",
                "Lodestar steers you to each panel in turn and tells you how far to rotate the camera. The screen shows progress, such as Panel 3 of 12. Take the shot, then tap **Shot taken \u{2192} Next**. The panels also appear on the sky chart.",
                "Tap **Finish** to end the mosaic.",
            ]),
            .tip("**Export Panels\u{2026}** on the Plan card saves the panel centers, with the camera angle, as a table or as a list of right ascension and declination for a planetarium or an ASIAIR. Plans in azimuth and altitude, such as the Milky Way arch, cannot be exported."),
            .tip("An object\u{2019}s page tells you when it needs a mosaic with your lens."),
            .caution("A mosaic cannot follow the Sun, Moon, planets, comets or asteroids, because they move against the stars. It also needs a rectilinear lens: with a fisheye profile in Settings the planner says so."),
        ],
        related: [.planFraming, .aimScreen])

    private static let trailsAndExposure = HelpTopic(
        topic: .trailsAndExposure, category: .planning, title: "Exposure, star trails and time-lapse", systemImage: "timer",
        summary: "Longest exposure, star trail and time-lapse planners.",
        keywords: ["npf", "500 rule", "startrails", "timelapse", "interval", "stacking", "shutter", "trailing", "polar alignment", "tools",
                  "tracker", "drift", "alt-az", "field rotation", "moon exposure", "looney 11", "iso"],
        blocks: [
            .paragraph("Stars drift across the sky, so a long exposure turns them into streaks. These tools help you pick an exposure that keeps stars sharp, or plan star trails and time-lapses on purpose."),
            .bullets([
                "Open them in **Settings** \u{25B8} **Tools**: **Exposure Calculator**, **Star Trails & Time-Lapse**, **Polar Alignment** and **Red Torch**.",
                "The **Exposure Calculator** gives the longest exposure before stars trail. The NPF rule counts your aperture and pixel size, so it suits high-resolution sensors. The 500 rule is simpler but too generous for them.",
                "Below the result, **Tracked** shows how fast a star tracker drifts when its axis is off the pole, and the longest exposure for the polar alignment error you set. It is the worst case, for a target 90\u{00B0} from the direction of the error.",
                "**Alt-Az Mount** shows how fast the field turns on an alt-azimuth mount, and the longest exposure at your target\u{2019}s place. Without a target, set the altitude and azimuth yourself. Due east or west the field does not turn.",
                "**Moon** suggests a shutter time for the Moon from the Looney 11 rule: f/11 at 1/ISO for a full Moon, with more light for a thinner or lower Moon. It uses your aperture and the ISO you pick, and shows how many pixels the Moon spans at your focal length.",
                "**Star Trails & Time-Lapse** plans how long to shoot for a trail, how to stack short frames, and how many pictures, how much time and how much storage a time-lapse needs.",
                "**Polar Alignment** shows where the pole star stands against the celestial pole, as a clock position. It helps you aim a star tracker\u{2019}s axis at the pole. The **Tonight** tab has the same clock.",
                "The planners start from your camera in Settings. Changes you make in a planner stay in that planner.",
                "Each object\u{2019}s page also shows the longest exposure before stars trail. The page of the Sun, the Moon or a planet shows how many pixels it spans at your focal length.",
            ]),
            .tip("Stars near the celestial pole move more slowly, so you can expose longer when you aim toward it."),
            .caution("These limits are rules of thumb. Check the stars in your first test frame at full size."),
        ],
        related: [.objects, .glossary])

    private static let skyline = HelpTopic(
        topic: .skyline, category: .planning, title: "Record your skyline", systemImage: "mountain.2",
        summary: "Teach Lodestar where trees and hills hide the sky, or let it work out the hills from elevation data.",
        keywords: ["horizon", "trees", "buildings", "hills", "mountains", "obstructions", "sweep", "saved site", "rise and set",
                   "terrain", "elevation", "terrain horizon"],
        blocks: [
            .paragraph("Trees, buildings and hills hide objects long before the true horizon. Record your site\u{2019}s real skyline once. Rise and set times, Tonight, the object pages and the sky chart then use it, and the Aim screen shades the ground below it."),
            .steps([
                "Go to your site and choose it in **Settings** \u{25B8} **Location**. A skyline belongs to a saved site, so for **Current Location** Lodestar offers to save it as a site first.",
                "Tap the mountain button on the site, or edit the site and open its **Horizon** section. Choose **Record Skyline\u{2026}**, or **Clear Skyline\u{2026}** to remove one.",
                "Hold the phone so its back camera points at the skyline, with the line on the crosshair. Turn slowly all the way around. Sweep back over a stretch to redo it.",
                "The screen shows how much is covered and what is still to sweep. **Start Over** begins again.",
                "Tap **Done** to save. If the circle is not complete, Lodestar asks what to do with the gaps.",
            ]),
            .paragraph("**Terrain horizon.** Where you cannot sweep, or have swept only part of the circle, Lodestar can work out the skyline of the hills and mountains from elevation data. Switch on **Terrain horizons** in **Settings** \u{25B8} **Online Data**, edit the saved site and, in its **Terrain Horizon** section, tap **Compute from Elevation Data\u{2026}**. Lodestar asks first, downloads up to four elevation tiles of about 11 MB each, works out the skyline and deletes the tiles. The tile server sees your IP address and which 1\u{00B0} tiles you request. Then the Aim screen, Tonight, the object pages and the sky chart use the terrain horizon wherever you have not recorded a skyline, and in the stretches a partial sweep left open. They say which skyline applies: **Recorded skyline**, **Terrain horizon** or **Recorded + terrain**. The same section offers the ground elevation of the data as the site\u{2019}s elevation, and **Remove Terrain Horizon\u{2026}**."),
            .tip("Record in daylight, when the camera picture shows the skyline. It helps you keep the line on the crosshair."),
            .caution("A skyline belongs to one spot. If you move a site by more than about 100 m, record it again. The terrain horizon is computed for the saved position, so compute it again after moving a site. It comes from a surface model: ridges narrower than about 30 to 90 m, trees and buildings nearby are not in it."),
        ],
        related: [.tonight, .objects])

    private static let sites = HelpTopic(
        topic: .sites, category: .planning, title: "Observing sites", systemImage: "mappin.and.ellipse",
        summary: "Save places, and see how dark their sky is.",
        keywords: ["site", "location", "dark sky", "bortle", "light pollution", "sky quality", "satellite", "night lights", "horizon glow", "darkest direction", "sqm"],
        blocks: [
            .paragraph("A **saved site** lets you plan a trip before you get there: choose it in **Settings** \u{25B8} **Location** and every screen works out the sky for it. **Add Site\u{2026}** takes a place from the map or from coordinates."),
            .paragraph("Under each site, and under **Current Location**, a line says how dark the sky is there, for example **Sky: Bortle ~4 (rural/suburban transition)**. Tap it to read how it is estimated."),
            .bullets([
                "The **Bortle scale** rates a night sky from class 1, a pristine dark sky, to class 9, an inner-city sky. Class 4 is the edge of the countryside, where the Milky Way is still easy to see; at class 7 and above it is hard to find.",
                "Lodestar works the class out on the phone from a map of the artificial light that satellites saw at night in 2016 (NASA Black Marble). It adds up the light of the towns within about 100 km of the site, the nearest counting most.",
                "The map has one cell for every 11 km, so it is a guide, not a measurement. It is good to about one class near a city and two in the dark, where it cannot tell class 1 from class 3. New lights, dark-sky rules and the sky\u{2019}s own glow are not in it. A meter reading (SQM) is better when you have one.",
                "On **Tonight**, the **Sky quality** card also names the direction where the sky is darker, and scores the night for imaging. On the **Sky Chart**, a thin **Horizon glow** ring is brighter toward the lights; turn it off in the layers menu or in **Settings** \u{25B8} **Sky Display**.",
            ]),
            .tip("For a darker sky, drive away from the bright side: the card tells you which compass direction that is."),
            .caution("A dark cell next to a town can still have a bright sky. Check the direction of the lights before you set up."),
        ],
        related: [.tonight, .skyline, .skyChart])

    /// The topics of "Sky and objects" and "Planning a picture".
    private static let sessionLog = HelpTopic(
        topic: .sessionLog, category: .planning, title: "Session log", systemImage: "book.closed",
        summary: "A private diary of what you shot, with CSV and OpenAstronomyLog export.",
        keywords: ["diary", "notes", "imaged", "export", "csv", "openastronomylog", "oal", "frames", "iso", "exposure", "astrobin"],
        blocks: [
            .paragraph("The session log records what you shot or tried on each night. It stays on this iPhone, and Lodestar never sends it anywhere."),
            .steps([
                "Open an object in **Objects** and tap **Log a Session** on its page. The form starts with now, your site, the lens from Settings and the longest exposure before stars trail. Fill in the ISO, the number of frames, the filter and your notes, and turn on **Imaged** when you got the shot.",
                "The object\u{2019}s earlier entries are listed under the button. Tap one to edit it, or the trash button to delete it.",
                "Open **Settings** \u{25B8} **Session Log** to see every entry grouped by night, search them and swipe to delete.",
                "Tap **Export** for a **CSV Table**, which opens in any spreadsheet, or an **OpenAstronomyLog** file (version 2.1), which logging programs read. Both go through the Files save sheet.",
            ]),
            .bullets([
                "A night runs from noon to noon at your site, so frames shot after midnight belong to the evening before.",
                "In **Objects**, a check mark shows the objects you imaged, and **Imaged Only** in the menu lists just those.",
                "The log holds 5,000 entries.",
            ]),
            .tip("Export a copy now and then: the log lives only on this device and is lost if you delete the app."),
        ],
        related: [.objects, .trailsAndExposure])

    static let sky: [HelpTopic] = [objects, skyChart, tonight, events, planFraming, mosaic, trailsAndExposure, skyline, sites, sessionLog]
}
