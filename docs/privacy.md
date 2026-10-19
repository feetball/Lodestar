---
title: Lodestar privacy policy
---

# Privacy policy

*Effective October 18, 2026*

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
- **Saved sites and settings** are stored only on your iPhone (and in your device backups, as for any
  app).

## Network use

Lodestar's catalogs and calculations are all on the device. By default the only network requests go to Apple:

- **Apple Maps** loads map tiles when you open the site map.
- **Apple's geocoding service** receives the coordinates of an observing site you add or edit, to look
  up its time zone.

Apple handles these requests under its own privacy policy (<https://www.apple.com/legal/privacy/>).
If you choose to share analytics with app developers in iOS Settings, Apple may provide anonymous crash
reports to the developer.

GoTo mount control talks to your telescope mount over your local Wi-Fi network only; nothing about it leaves
that network.

## Optional online data (off by default)

Settings ▸ Online Data has four switches. **All of them are off** until you turn them on, and Lodestar works fully
without them. Each switch makes ordinary HTTPS requests to one provider to download data to your iPhone:

| Switch | What is downloaded | Provider | What the provider receives |
| --- | --- | --- | --- |
| Satellite passes | Orbit data of the ISS and other bright satellites (about 75 KB, at most every 12 to 24 hours) | [CelesTrak](https://celestrak.org) | Your IP address |
| Starlink streak warnings | Orbit data of the Starlink satellites (about 4.7 MB, once a day, only on a network that is not expensive or in Low Data Mode, such as Wi-Fi) | [CelesTrak](https://celestrak.org) | Your IP address |
| Comets | The comet orbit file (about 164 KB, at most once a day) | [Minor Planet Center](https://minorplanetcenter.net) | Your IP address |
| Cloud forecast | The hourly cloud-cover forecast (about 64 KB, no more often than the provider allows) | [MET Norway](https://api.met.no) | Your IP address and your location **rounded to 0.1° (about 10 km)** |

Every request also carries the app's name and version (for example `Lodestar/1.0`) and the address of the support
page, as the providers require. Nothing else about you or your iPhone is sent: no account, advertising identifier,
device identifier or exact location. Lodestar does not keep a server of its own and never sees these requests.

- The downloads happen when you open the app, when you switch a feed on and when you press **Update now**; nothing
  runs in the background.
- The downloaded data is stored only on your iPhone, in a folder that is excluded from device backups.
- Turning a switch off deletes the data it downloaded.
- A failed or unreadable download never replaces the data you already have.

The providers keep their own server logs under their own policies: see the websites of
[CelesTrak](https://celestrak.org) and the [Minor Planet Center](https://minorplanetcenter.net), and
[MET Norway's privacy statement](https://www.met.no/en/About-us/privacy). Orbital data: CelesTrak, T. S. Kelso.
Orbital elements: IAU Minor Planet Center. Weather forecast from MET Norway (data licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)).

## Children

Lodestar does not collect personal information from anyone, including children.

## Changes and contact

If this policy changes, the new version will be posted on this page with a new effective date.
Questions are welcome on the project's issue tracker: <https://github.com/feetball/Lodestar/issues>.
