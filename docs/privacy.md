---
title: Lodestar privacy policy
---

# Privacy policy

*Effective November 20, 2026*

Lodestar is designed to work entirely on your iPhone. **It does not collect any data about you.** There
are no accounts, no analytics, no advertising and no tracking, and the developer never receives your
location or anything else from the app.

## What the app uses, and why

- **Location.** Your position (precise or approximate, as you allow) is used on your iPhone to work out
  where stars and planets appear in your sky and to find true north. It is not stored on any server.
  You can instead choose observing sites on a map.
- **Camera.** If you turn on the camera view, the live picture is shown behind the sky overlay. Video
  is processed on your iPhone only and is never recorded, stored or sent anywhere.
- **Motion sensors.** The gyroscope, accelerometer and compass are read on your iPhone to tell where
  your camera points.
- **Photos.** *From a Photo…* in Settings ▸ Camera & Lens uses the iOS photo picker, so Lodestar sees only the one
  picture you choose. It reads that picture's metadata (the camera, focal length and aperture) on your iPhone, and
  does not keep the picture or send it anywhere.
- **Saved sites and settings** are stored only on your iPhone (and in your device backups, as for any
  app).

The Home Screen and Lock Screen widgets and the Apple Watch app (with its watch-face complications) use the location of
the device they run on, your iPhone or your watch, only on that device, to work out when it gets dark and where the Moon
and the Milky Way are tonight. They make no network requests and send nothing anywhere. The iPhone app can also pass
your observing place to a paired watch, and, while you aim at a target with the watch app open, the aiming values (the
pan and tilt to make, the distance to go and the target's name), over the direct connection between the two devices;
none of it goes to a server.

## Network use

Lodestar's catalogs and calculations are all on the device. By default the only network requests go to Apple:

- **Apple Maps** loads map tiles when you open the site map.
- **Apple's geocoding service** receives the coordinates of an observing site you add or edit, rounded to about 1 km, to
  look up its time zone (and again later if the site was saved without a network).

Apple handles these requests under its own privacy policy (<https://www.apple.com/legal/privacy/>).
If you choose to share analytics with app developers in iOS Settings, Apple may provide anonymous crash
reports to the developer.

GoTo mount control talks to your telescope mount over your local Wi-Fi network only; nothing about it leaves
that network.

## Optional online data (off by default)

Settings ▸ Online Data has five switches. **All of them are off** until you turn them on, and Lodestar works fully
without them. Each switch makes ordinary HTTPS requests to one provider to download data to your iPhone:

| Switch | What is downloaded | Provider | What the provider receives |
| --- | --- | --- | --- |
| Satellite passes | Orbit data of the ISS and other bright satellites (about 75 KB, at most every 12 to 24 hours) | [CelesTrak](https://celestrak.org) | Your IP address |
| Starlink streak warnings | Orbit data of the Starlink satellites (about 4.7 MB, once a day, only on a network that is not expensive or in Low Data Mode, such as Wi-Fi) | [CelesTrak](https://celestrak.org) | Your IP address |
| Comets | The comet orbit file (about 164 KB, at most once a day) | [Minor Planet Center](https://minorplanetcenter.net) | Your IP address |
| Cloud forecast | The hourly cloud-cover forecast (about 64 KB, no more often than the provider allows) | [MET Norway](https://api.met.no) | Your IP address and your location **rounded to 0.1° (about 10 km)** |
| Terrain horizons | Only when you ask a site for its terrain horizon: up to four 1° elevation tiles (about 11 MB each), deleted as soon as the skyline is computed | [AWS Open Data Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) (Amazon S3, s3.amazonaws.com) | Your IP address and **which 1° tiles you request**, which is where the site is to within about 100 km |

Every request also carries the app's name and version (for example `Lodestar/1.0`) and the address of the support
page, as the providers require. Nothing else about you or your iPhone is sent: no account, advertising identifier,
device identifier or exact location. Lodestar does not keep a server of its own and never sees these requests.

- The downloads happen when you open the app, when you switch a feed on and when you press **Update now**; nothing
  runs in the background. Terrain horizons download only when you ask for one in a site's editor, after a question that says
  how much will be downloaded.
- The downloaded data is stored only on your iPhone, in a folder that is excluded from device backups.
- Turning a switch off deletes the data it downloaded. The elevation tiles are deleted as soon as the skyline is computed;
  the skyline itself (360 numbers) stays with the site until you remove it.
- A failed or unreadable download never replaces the data you already have.

The providers keep their own server logs under their own policies: see the websites of
[CelesTrak](https://celestrak.org) and the [Minor Planet Center](https://minorplanetcenter.net), and
[MET Norway's privacy statement](https://www.met.no/en/About-us/privacy) and the
[AWS Privacy Notice](https://aws.amazon.com/privacy/) for the tile server. Orbital data: CelesTrak, T. S. Kelso.
Orbital elements: IAU Minor Planet Center. Weather forecast from MET Norway (data licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)). Terrain elevation data from the AWS Open Data Terrain Tiles
(SRTM and GMTED2010 courtesy of the U.S. Geological Survey, and the other sources credited in the app under Data Credits).

## Children

Lodestar does not collect personal information from anyone, including children.

## Changes and contact

If this policy changes, the new version will be posted on this page with a new effective date.
Questions are welcome on the project's issue tracker: <https://github.com/feetball/Lodestar/issues>.
