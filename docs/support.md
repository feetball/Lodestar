---
title: Lodestar support
---

# Support

The app has the same guides, and more, built in: **Settings ▸ Help** is a searchable list of pages for every
screen, and the **?** buttons on Aim, Sky, Tonight, Events and Objects open the page that belongs to them.

## Getting started

1. Mount your iPhone rigidly on the camera (a hot-shoe or tripod phone mount works) and choose that
   mount in **Settings ▸ Mount**. Enter your camera's sensor and lens in **Settings ▸ Camera & Lens**.
2. Allow location access (approximate is fine) or choose an observing site on the map.
3. **Align** on a bright star or planet: centre it in your camera's viewfinder or live view and tap
   **Sync**. For best results, align on a star near your target, or add a second star far from the first.
4. Pick a target and follow the arrows until Lodestar says it is in your frame, then fine-tune in your
   camera's live view.

## Frequently asked questions

**How accurate is it?** Sky positions are computed to arcseconds. The limit is the phone's compass,
which camera bodies and metal tripods can disturb by several degrees. Star alignment removes most of
that error, and **Gyro Lock** (Settings ▸ Mount) keeps the compass out of it afterwards.

**The arrows seem wrong.** Check **Settings ▸ About ▸ Sensor Diagnostics**: with the phone upright and
the camera facing north, the gravity check should read PASS. Make sure the mount setting matches how the
phone sits on the camera, then align on a star.

**How do I make the whole screen red?** Lodestar's night mode is red, but some system elements
(keyboard, menus) cannot be tinted by apps. For a fully red screen, set up iOS **Color Filters** (Settings
▸ Accessibility ▸ Display & Text Size ▸ Color Filters ▸ Color Tint, intensity and hue at maximum) and
assign it to the Accessibility Shortcut (triple-click the side button).

**Does it need an internet connection?** No. Everything works offline. The site map and the time-zone
lookup for a new site use the network, and **Settings ▸ Online Data** has optional downloads (satellite
passes, Starlink streak warnings, comets and a cloud forecast) that are all off until you switch them on.
Each one tells you what it sends; see the [privacy policy](privacy.html).

**Online Data: "The last update failed".** Lodestar keeps the data you already have. CelesTrak answers
repeated requests for unchanged data with an error, so Lodestar asks for each satellite list at most every
two hours; wait and try **Update now** later. The Starlink list (4.7 MB) downloads only on Wi-Fi.

## Contact

Report a problem or ask a question on the issue tracker: <https://github.com/feetball/Lodestar/issues>.

## Credits

Star data: HYG Database v4.1 (CC BY-SA 4.0). Deep-sky data: OpenNGC (CC BY-SA 4.0). Constellation figures
and Milky Way outlines: d3-celestial (BSD-3-Clause). Geomagnetic model: NOAA/BGS WMM2025. Optional
downloads: orbital data: CelesTrak, T. S. Kelso; orbital elements: IAU Minor Planet Center; weather
forecast from MET Norway (CC BY 4.0).
