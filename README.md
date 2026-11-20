# Lodestar

**Aim your camera at the night sky.** Lodestar turns an iPhone clamped to your camera into a smart
finder: pick a planet, nebula, galaxy or star, and on-screen arrows tell you which way to pan and
tilt the tripod head until it is in your frame.

> A *lodestar* is the star that guides a traveller — traditionally Polaris. This one guides your lens.

## Features

- **Guided aiming** — a live finder (camera view or virtual sky) with the target marker, an arrow
  pointing the shortest way, "Pan right 23.4° / Tilt up 12.1°" read-outs for pan-tilt heads, the
  distance to go, an on-target state with haptics, optional audio ticks that speed up as you get
  closer, a level gauge, and the outline of *your* camera's frame (from sensor size and focal length).
  Keep a **camera profile** for each body and lens, start from a smart-telescope preset (Seestar, Dwarf,
  Vespera) or read a profile from a photo's EXIF data, and switch with one tap; a **fisheye** lens gets a
  curved or circular frame. With no target it names what is in the middle of the picture, and the camera
  picture zooms up to 8×.
- **Star alignment** — centre a bright star or planet in your camera once and Lodestar learns
  the compass error and the bracket's misalignment (one star: heading + tilt; two or more: a
  least-squares fit with residuals). Syncing waits until the phone has been held still, each
  reference star shows its distance from the stars already synced (with a warning under 20°), and
  an alignment that is hours old gets a warning chip. Optional **Gyro Lock** keeps the heading on
  the gyroscope so the camera body's magnetism cannot disturb it.
- **Works for any mount** — back camera along the lens (portrait, upside down, landscape) or the
  phone lying flat on top of the camera.
- **Objects** — search (names, Messier/NGC/IC/HR/HD/HIP numbers, Greek-letter star names in any
  spelling) or browse by group: Solar System, Stars, Galaxies, Nebulae, Star Clusters, Special
  (Milky Way core, celestial poles). Sort by name, brightness, altitude, rise time or the hours an
  object is visible tonight above your recorded skyline, and filter to objects visible for at least
  an hour tonight; favourites, recents and custom RA/Dec targets. Each object shows where it is now with its hour angle and the
  time to its meridian transit, its rise/transit/set, an altitude chart over the night with twilight
  shading, how it fits your frame, the longest exposure before stars trail (NPF and 500 rules) and
  how much the Moon will matter. That advice is filter-aware: set a light-pollution or narrowband
  filter in *Settings ▸ Camera & Lens* and it is relaxed for emission nebulae, planetary nebulae and
  supernova remnants. Tonight's best targets weigh the Moon the same way.
- **Sky chart** — an all-sky planisphere with constellations, the Milky Way, planets and deep-sky
  objects, your camera's live pointing, tap-to-identify, time travel and zoom up to 15×. **Plan your
  framing** holds your camera's frame in the middle of the chart so you can move the sky under it and
  turn it (position angle for a tracker, roll for a tripod) without holding the phone up.
- **Help** — a searchable guide to every screen in *Settings ▸ Help*, and ? buttons on the screens that
  open the page that belongs to them.
- **Tonight** — sunset, twilight and darkness windows, the Moon (phase, illumination, rise/set,
  moon-free dark hours), when the Milky Way core is up, which planets are visible, the best
  targets of the night (with a recorded skyline, ranked by the hours they stay clear of it), and a
  polar-scope clock for star trackers. A **Sky quality** card estimates the
  Bortle class of the site offline from satellite night-light imagery, points to the darkest direction and
  scores the night for imaging (dark hours, Moon, sky brightness and, when the forecast is on, clouds); the
  same estimate shows on every site, and the sky chart can draw a thin glow ring on the horizon.
- **Events calendar** — meteor showers (with hourly rates, the radiant's altitude from your site, the best camera
  direction, away from the radiant and the Moon, and how many meteors to expect in your lens's frame), lunar and
  solar eclipses, conjunctions, oppositions and elongations, supermoons, equinoxes and solstices, the stations
  of the planets, and for planet imagers the Great Red Spot's transits and the Galilean moons' transits, shadows
  and eclipses (with a "Moons tonight" diagram on Jupiter's screen), each with when and where to look and a button
  to aim at it.
- **Photo planners** — a mosaic planner for panoramas such as the Milky Way arch (panels, overlap and shooting
  order, guided panel by panel in Aim), and star-trail and time-lapse planners.
- **Exposure calculator** — the longest exposure before stars trail by the NPF, 500, 400 and 300 rules for your
  camera, lens and target; for a star tracker, the drift and the limit for a polar-alignment error of 0.1° to 5°;
  for an alt-azimuth mount, the field-rotation rate and the limit at the target's place; and a shutter time for the
  Moon by the Looney 11 rule, adjusted for phase and height, with the Moon's size in pixels. The pages of the Sun,
  Moon and planets show their size in pixels too.
- **Real skyline** — sweep the phone along the horizon to record trees, buildings and mountains; rise and set
  times, Tonight and the charts then use the site's own skyline. Optionally, a **terrain horizon** worked out from
  elevation data (AWS Open Data, downloaded for a saved site only when you ask) stands in where you have not
  recorded a skyline and fills the stretches a partial sweep left open.
- **Comets and asteroids** — 216 bright asteroids built in and, optionally, the daily comet file: brightness
  estimates, elongation warnings, a Bright Comets list, and the direction of a comet's ion tail with the camera
  tilt that lays it along the frame.
- **GoTo mounts** — connect over Wi-Fi to OnStep/LX200, Celestron NexStar and SynScan, ASCOM Alpaca and the
  Sky-Watcher AZ-GTi / Star Adventurer GTi (with home position and star alignment); Go to, Sync, nudge arrows and
  an always-available Stop, with altitude limits, a meridian countdown that warns before the mount has to flip,
  and a built-in simulated mount to try it without hardware.
- **Optional online data** — all off until switched on in Settings: ISS and bright-satellite passes (follow one in
  Aim), Starlink streak warnings for the planned exposure, fresh comet orbits, and tonight's cloud forecast with dew,
  wind, fog and temperature (MET Norway, location rounded to about 10 km) and terrain horizons (elevation tiles from
  AWS Open Data, only when you ask a site for one).
- **Widgets and Apple Watch** — Home Screen and Lock Screen widgets (small, medium, circular,
  rectangular, inline) and watch complications (circular, rectangular, inline, corner) show tonight
  at a glance: when it is dark, the Moon, when the Milky Way core is up and the next event. They are
  worked out on the device for where you are (Core Location in the widget, no App Group, no network),
  and a tap opens the Tonight tab. The watch app adds a small Tonight screen.
- **Night mode** — a pure red-on-black interface (no green or blue light at all), automatic after
  sunset, with screen dimming and a red-filtered camera view. Lodestar also explains how to set up
  iOS Color Filters for a system-wide red screen.
- **Offline and private** — all catalogs and ephemerides are on the device; nothing is collected.
  The optional online data downloads from CelesTrak, the Minor Planet Center, MET Norway and AWS Open Data only
  when you turn it on, and a GoTo mount is reached over the local network only.

## Requirements

- Xcode 16 or newer (tested design targets Xcode 16 and Xcode 26), iOS 17.0+ deployment target
  (watchOS 10.0+ for the watch app and its complications).
- An iPhone with gyroscope and magnetometer (every iPhone that runs iOS 17). The simulator has no
  motion sensors, so aiming only works on a device.
- A bracket that holds the phone rigidly on the camera (hot-shoe phone mount, L-bracket clamp, …).

## Getting started

1. Open `Lodestar.xcodeproj` (Xcode 16+ project format with a synchronized `Lodestar/` folder and the
   local Swift package `LodestarKit`).
2. Select the **Lodestar** target ▸ *Signing & Capabilities*, choose your team, and change the bundle
   identifier (`net.kuecker.Lodestar`) if needed.
3. Build and run on your iPhone.

Prefer generating the project? `project.yml` describes the same project for
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (2.45.4 or newer): `xcodegen generate`.

### Using it in the field

1. Mount the phone so it does not move relative to the camera, and pick that mount in
   *Settings ▸ Mount*. Enter your camera's sensor and lens in *Settings ▸ Camera & Lens*.
2. Allow location access (approximate location is fine) or choose an observing site on the map.
3. *Align*: pick a bright star or planet, centre it in your camera's viewfinder or live view, tap
   **Sync**. For best results sync on a star near your target, or add a second star far from the
   first. Re-align if you remount the phone.
4. Pick a target and follow the arrows until Lodestar says you are on target, then fine-tune in
   your camera's live view.

**Accuracy.** The sky positions are far more precise than the sensors (see below). Phone compasses
are typically good to a few degrees and are easily disturbed by camera bodies, lenses and metal
tripods; star alignment removes most of that error, and Gyro Lock keeps it out. Expect to land within
a degree or so of the target after alignment — inside the frame of all but long telephoto lenses.

## How it is built

```
Lodestar/            iOS app (SwiftUI, Observation, Swift 5 mode with complete concurrency checking)
  App/ Model/ Theme/ Shared/     app state, settings, palette (normal + red night), shared views
  Services/          location, device motion (CoreMotion), camera (AVFoundation + CoreImage),
                     haptics/audio, screen brightness, catalog loading, time-zone lookup
  Features/          Aim, Objects, SkyChart, Tonight, Settings, Onboarding, Tools, Widgets (links, watch link)
LodestarWidgets/     iOS widget extension: the Home Screen layouts of the Tonight widget
LodestarWatch/       Apple Watch app (watchOS 10, embedded in the iPhone app): the Tonight screen
LodestarWatchWidgets/  watch complications
WidgetShared/        what the three share: tonight's entries from LodestarKit (no catalog), the location,
                     the timeline provider, the Lock Screen / complication views and the widget look
LodestarKit/         Swift package, Foundation only, builds and tests on macOS and Linux
  Foundation/        time scales, coordinates, precession/nutation/aberration, refraction, SkyFrame
  Ephemeris/         Sun & planets (VSOP87), Pluto (Meeus), Moon (ELP-2000/82 after Meeus), rise/set,
                     twilight, phases
  Catalog/           bundled star/deep-sky/constellation/Milky Way data, search, sorting
  Pointing/          CoreMotion attitude → camera pointing, mounts, star-alignment solver, guidance
  Planning/          night summary, darkness and Moon windows, Milky Way core, best targets, polar scope
  PhotoTools/        sensor formats, field of view, NPF/500-rule exposure limits, polar-error drift, field rotation, Moon exposure
  Formatting/        angle/coordinate formatting and robust parsing
  Geomagnetism/      World Magnetic Model 2025 (declination, field strength)
  Resources/         stars.json (9,001 stars), dsos.json (693 objects incl. all 110 Messier),
                     constellations.json (88), milkyway.json
Tools/               reproducible generators for the bundled data, coefficients, icon and test fixtures
```

Key design points:

- **Pointing.** CoreMotion's attitude (magnetic-north reference + WMM2025 declination, so it works
  without Location Services) is turned into the camera's boresight in the local East-North-Up frame,
  corrected by the alignment model, and compared with the target's *apparent* (refracted) position.
  All frame conventions are documented in `LodestarKit/Sources/LodestarKit/Pointing/DeviceAttitude.swift`.
- **Positions.** Catalog stars are propagated with proper motion, precession, nutation and annual
  aberration; Sun, Moon, planets and Pluto come from analytic theories with light-time and
  topocentric parallax. Against JPL DE440s: Sun 0.2″, planets ≤ 5″, Pluto ≤ 1.4″ in 1950–2049 (its
  series is valid only for 1885–2099), Moon ≤ 8″; rise/set times within about a second of an
  independent reference; Moon phases within 16 s.
- **Concurrency.** Sensor callbacks run off the main thread and hand Sendable samples to the UI
  through a lock-protected box that the 30 fps overlay polls; heavy sky computations run in detached
  tasks.

## Tests

```
cd LodestarKit && swift test          # 700+ tests: worked examples from Meeus and Skyfield/JPL fixtures
cd WidgetTests && swift test          # the widgets' entries and wording (WidgetShared/Core, no Xcode needed)
```

The `Lodestar` scheme's Test action runs the same package tests in Xcode.

## Continuous integration and releases

- **GitHub Actions** (`.github/workflows/ci.yml`) compiles the app with the newest Xcode for the
  simulator and for devices, and runs the LodestarKit tests, on every push and pull request. The
  `Lodestar` scheme also builds the widget extension, the watch app and the complications, and
  `Tools/check-embedded-products.sh` checks that all three end up inside the app.
- **Xcode Cloud** (workflow "Default") builds and archives the app on every push to `main` and
  delivers each build to TestFlight's internal testing group. Xcode Cloud signs the builds and
  assigns the build numbers; workflows are managed in App Store Connect under the app's
  *Xcode Cloud* tab.

## Before relying on it — check on your device

This project was written without access to Xcode or an iPhone; the engine is verified by its test
suite and the app was type-checked against stand-ins for the iOS SDK, but a few things can only be
confirmed on hardware. *Settings ▸ About ▸ Sensor Diagnostics* helps with the first two:

1. **Sensor convention.** With the phone upright and the camera facing north, the gravity check
   should read PASS; laid flat with the top edge toward a known compass bearing, the "top-edge
   heading" should match the Compass app.
2. **Arrow direction.** Pick a target, move the tripod the way the arrow says, and confirm the
   distance shrinks (pan and tilt separately).
3. **Overlay registration.** With the camera preview on, bright stars or the Moon should sit on
   their labels.
4. **Night mode.** Some system elements (keyboard, menus, alerts) cannot be tinted by apps; use iOS
   Color Filters for a fully red screen (*Settings ▸ Night Mode* explains how).
5. Open the project in your Xcode version and build once; report any compiler errors.

## Privacy

Lodestar has no accounts, analytics, ads or tracking, and it never collects your data: location, motion
and camera data are processed on the device. The network is used by Apple (map tiles in the site picker,
and the geocoding service, which receives a site's coordinates to look up its time zone while you add or
edit a site) and by the optional downloads in Settings ▸ Online Data, which are off until switched on:
CelesTrak, the Minor Planet Center, MET Norway and the AWS Open Data tile server see the IP address; MET
Norway also sees the location rounded to about 10 km, and the tile server which 1° elevation tiles you ask for
(where a site is to within about 100 km), only when you ask a site for its terrain horizon. GoTo mount control
talks to the mount on the local network only. See
`docs/privacy.md` and `Lodestar/Resources/PrivacyInfo.xcprivacy`.

## Data and credits

Star data: HYG Database v4.1 (CC BY-SA 4.0). Deep-sky data: OpenNGC (CC BY-SA 4.0). Constellation
figures and Milky Way outlines: d3-celestial (BSD-3-Clause). Geomagnetic model: NOAA/BGS WMM2025
(public domain). Planetary theory VSOP87 (Bretagnon & Francou); Pluto and lunar theory after
J. Meeus. Night lights: NASA Worldview / GIBS, Black Marble (VIIRS, Suomi NPP). Optional terrain elevation data: AWS Open Data Terrain Tiles (SRTM and GMTED2010 courtesy of the U.S.
Geological Survey, and national surveys). Full details, licences and regeneration instructions: [ATTRIBUTION.md](ATTRIBUTION.md)
and [Tools/README.md](Tools/README.md). The derived data files remain under CC BY-SA 4.0.
