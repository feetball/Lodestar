# Reference fixtures for LodestarKit's astronomy tests

The JSON files in this directory are independent reference data. They were computed with
[Skyfield](https://rhodesmill.org/skyfield/) 1.55 and the JPL DE440s planetary ephemeris by
`Tools/make_fixtures.py`; no LodestarKit code was used. Unit tests compare LodestarKit against
them with explicit tolerances. Never edit the JSON by hand: change the generator and
regenerate (see [Regenerating](#regenerating)).

| File | Bytes | Content | Size |
| --- | ---: | --- | --- |
| `sidereal.json` | 32,193 | time scales, GMST/GAST, nutation, obliquity, precession and nutation matrices, Earth velocity | 44 instants |
| `stars_apparent.json` | 106,148 | apparent place and horizontal coordinates of 12 bright stars | 240 cases |
| `bodies_apparent.json` | 270,793 | Sun, Moon and 7 planets: apparent places, horizontal coordinates, phase, distances | 450 cases |
| `riseset.json` | 95,481 | rise, set, transit and twilight crossings | 30 windows x 6 objects |
| `moon_phases.json` | 28,252 | new/quarter/full moons 2024-2028 plus illumination samples | 248 phases, 30 samples |

The JSON files total 532,867 bytes (budget: 1.5 MB).

## Read this first

**1. Time convention (all files).** Every instant has an ISO-8601 `utc` string, `ut1_jd` and
`tt_jd`. The `utc` string is read as **UT1** (DUT1 = 0), exactly what `JulianDate(date:)` assumes
(UT is approximately UTC), so `Date(utc)` and `ut1_jd` are the same instant. Skyfield's own
UTC-to-UT1 conversion is deliberately not used: before 1972 Skyfield has no UTC (it would move
1950-1971 instants by up to 13 s) and its extrapolated DUT1 reaches -2.1 s by 2049. TT is
`UT1 + delta_t_seconds`, where Delta T comes from Skyfield's built-in tables (IERS daily values
1973-01-02..2027-01-23, Stephenson/Morrison/Hohenkerk splines before and an extrapolation after).
**Whenever a test depends on TT, build `JulianDate(ut: ut1_jd, deltaT: delta_t_seconds)`**
(ephemerides, precession, nutation, aberration). A different Delta T model shifts the bodies:
the Moon moves 0.55 arcsec per second of error, the Sun 0.04 arcsec/s. For scale, the
Espenak-Meeus 2006 polynomial exceeds these files' Delta T by 5 s in 2024, 10 s in 2031 and 15 s
in 2040. Earth rotation (sidereal time, hour angle) depends only on UT1 and is unaffected.

**2. The Moon's rise/set threshold in DESIGN.md is inconsistent; two lists are provided.**
DESIGN.md section 4.1 asks for the *topocentric* altitude of the Moon's centre to cross
`h0 = 0.7275 pi - 0.5667 deg` (pi = horizontal parallax). That is Meeus' threshold for the
*geocentric* altitude of the centre; the parallax pi is already part of the topocentric altitude,
so the literal recipe places the event about pi (0.95 deg) too high: moonrise comes late and
moonset early. `riseset.json` therefore contains, for the Moon:

* `horizon`: the DESIGN.md recipe taken literally (kept so that it can be reproduced);
* `horizon_upper_limb`: topocentric centre altitude crossing
  `h0 = -0.5667 deg - asin(1737.4 km / topocentric distance)`, the instant the upper limb is on
  the horizon after 34' of refraction. This is the USNO and JPL Horizons definition, and
  equals Meeus' recipe applied to the geocentric altitude to within 3 s (checked on all 49
  Moon crossings).

Measured error of the literal recipe against `horizon_upper_limb` (all 2026-2030 windows):

| Site | latitude | median | maximum |
| --- | ---: | ---: | ---: |
| quito | 0.0 | 255 s | 284 s |
| sydney | -33.9 | 317 s | 347 s |
| boulder | 40.0 | 357 s | 409 s |
| greenwich | 51.5 | 511 s | 572 s |
| tromso | 69.7 | 707 s | 949 s |

Against the US Naval Observatory the literal recipe is off by up to 16 minutes and
`horizon_upper_limb` by at most 30 s; against JPL Horizons the literal recipe is 5-6 minutes
off, `horizon_upper_limb` agrees within the 1-minute search resolution (see
[Validation](#validation)). **Recommendation:** fix DESIGN.md and the implementation (either
keep the topocentric altitude with `h0 = -0.5667 deg - semi-diameter`, or use the geocentric
altitude with `0.7275 pi - 0.5667 deg`) and test against `horizon_upper_limb`.

**3. "Geometric" altitude is not "airless geometric".** `alt_deg`/`az_deg` are the topocentric
direction of the *apparent* place without atmospheric refraction. They include annual aberration,
diurnal aberration (up to 0.32 arcsec, absent from a pipeline that uses only the Earth's orbital
velocity), gravitational light deflection by the Sun, Jupiter, Saturn and the Earth (usually
below 0.02 arcsec; up to 1.75 arcsec at the solar limb), and light time for solar-system bodies.
They are measured from the WGS84 geodetic vertical; polar motion is zero.

**4. Transits are maxima of altitude**, not meridian passages, and culminations below the
horizon are listed too (see [riseset.json](#risesetjson)).

## Conventions common to all files

* **Header.** Every file has `schema_version` (1; raised on incompatible changes),
  `generator` (`Tools/make_fixtures.py`),
  `skyfield_version` (`1.55`), `ephemeris` (name and SHA-256 of `de440s.bsp`), `description`,
  `notes` (the definitions of the file, as an array of sentences) and then its data sections.
* **Angles** are degrees. Right ascension is in [0, 360) degrees (never hours, except
  `gmst_hours`/`gast_hours`). Declination in [-90, 90]. **Azimuth is measured from North toward
  East**, [0, 360). Altitude in [-90, 90]. Distances are AU unless the name says otherwise.
* **Sites.** `lat` is WGS84 geodetic latitude in degrees, `lon` is east-positive longitude in
  degrees, `elevation_m` is the height above the WGS84 ellipsoid in metres. The six sites (in
  every file's `sites` array where used) are:

  | `site` | lat | lon | elevation_m |
  | --- | ---: | ---: | ---: |
  | `boulder` | 40.0 | -105.27 | 1650 |
  | `greenwich` | 51.48 | 0.0 | 0 |
  | `sydney` | -33.87 | 151.21 | 0 |
  | `tromso` | 69.65 | 18.96 | 0 |
  | `quito` | 0.0 | -78.5 | 2800 |
  | `paranal` | -24.63 | -70.40 | 2635 |

  `riseset.json` uses the first five.
* **Frames.**
  *Apparent place of date* = geocentric (or topocentric) direction including light time, light
  deflection and annual aberration, referred to the *true* equator and equinox of date (IAU 2006
  precession, IAU 2000A nutation).
  *Apparent place, J2000* (`..._j2000_deg` of a body) = the same direction on the ICRS axes, which
  are the mean equator and equinox of J2000.0 within 20 mas (frame bias).
  *Topocentric* = as seen from the site, including parallax and diurnal aberration.
* **Numbers.** JSON doubles. Julian dates keep full precision; angles are rounded to 1e-9 deg
  (3.6 microarcsec), AU to 1e-12, sidereal hours to 1e-10, matrices to 1e-15, event times to
  1 ms. Optional values are `null` (never `NaN`).
* **Event instants** (`riseset.json`, `moon_phases.json`) carry `utc` with millisecond text
  (`2026-10-17T20:01:13.385Z`) and `unix`, the POSIX seconds of that same calendar value
  (use it to avoid fractional-second ISO parsing).
* **Decoding in Swift.** The files decode with `JSONDecoder` and
  `keyDecodingStrategy = .convertFromSnakeCase` (`ut1_jd` becomes `ut1Jd`, `ra_j2000_deg` becomes
  `raJ2000Deg`, `h0_deg` becomes `h0Deg`). They are bundled as `resources: [.copy("Fixtures")]`:

  ```swift
  func loadFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                subdirectory: "Fixtures"))
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      return try decoder.decode(T.self, from: Data(contentsOf: url))
  }
  ```

  The `cases`, `phases` and `samples` of all five files were decoded with such structs under
  Swift 6.4 on Linux while writing this README (every field listed below, optional ones
  included).

## sidereal.json

`cases[]`: 44 instants, ascending: the four fixed ones (1987-04-10T00:00:00Z and
1987-04-10T19:21:00Z, Meeus examples 12.a and 12.b; 2000-01-01T12:00:00Z; 2026-10-17T00:00:00Z)
plus 40 seeded instants, one per 2.5-year stratum of 1950-2049.

| Field | Type | Definition |
| --- | --- | --- |
| `utc` | string | `YYYY-MM-DDTHH:MM:SSZ`, read as UT1 |
| `ut1_jd`, `tt_jd` | double | Julian date in UT1 and TT |
| `delta_t_seconds` | double | TT - UT1 (so `tt_jd - ut1_jd == delta_t_seconds / 86400`) |
| `gmst_hours` | double | Greenwich mean sidereal time, hours [0, 24), IAU 2006 (Skyfield `Time.gmst`) |
| `gast_hours` | double | Greenwich apparent sidereal time, hours [0, 24): `gmst` + equation of the equinoxes (IAU 2000A nutation plus complementary terms) |
| `nutation_dpsi_arcsec`, `nutation_deps_arcsec` | double | IAU 2000A nutation in longitude and obliquity |
| `mean_obliquity_deg` | double | IAU 2006 mean obliquity of the ecliptic of date (true obliquity = mean + `deps`/3600) |
| `precession_matrix` | 9 doubles | row-major 3x3 `P`, IAU 2006, mean equator/equinox of J2000.0 to mean of date: `v_date = P v_J2000`; frame bias not included |
| `nutation_matrix` | 9 doubles | row-major 3x3 `N`, IAU 2000A, mean of date to true of date: `v_true = N v_mean` (so `N P` takes a J2000 mean vector to the true equator of date) |
| `earth_beta_icrs` | 3 doubles | barycentric velocity of the Earth divided by c on the ICRS axes (includes the Sun's barycentric velocity, at most 16 m/s) |

Meeus' examples agree with these values to 3.3 ms of time (GMST 13h10m46.3701s here vs
13h10m46.3668s in the book, and 8h34m57.0929s vs 8h34m57.0896s): the book uses the IAU 1982
GMST formula, these files IAU 2006.

## stars_apparent.json

Top level: `sites` (6), `stars` (12), `cases` (240). The 12 stars are Sirius, Canopus, Arcturus,
Vega, Capella, Rigel, Betelgeuse, Polaris, Acrux, Altair, Deneb and sigma Octantis.
There are 10 instants (2000-01-01T12:00:00Z, 2026-10-17T00:00:00Z and 8 seeded ones over
1950-2049); instant number `i` (0-based, ascending) is evaluated at sites `i mod 6` and
`(i + 3) mod 6`, for every star: 10 x 2 x 12 = 240 cases.

Catalogue inputs (`stars[]`, repeated in every case so that a test feeds identical numbers to
LodestarKit): the Hipparcos catalogue (ESA 1997, VizieR I/239) ICRS J1991.25 positions moved to
J2000.0 with the catalogue proper motion. Parallax and radial velocity are taken as zero.

| Field | Type | Definition |
| --- | --- | --- |
| `utc`, `ut1_jd`, `tt_jd` | | the instant (see conventions) |
| `site`, `lat`, `lon`, `elevation_m` | | the observer |
| `star`, `hip` | string, int | name and Hipparcos number |
| `ra_j2000_deg`, `dec_j2000_deg` | double | ICRS position at J2000.0, degrees |
| `pmra_mas_per_year` | double | mu_alpha * cos(delta) in mas/yr (Hipparcos `pmRA`; this is `ProperMotion.raMilliarcsecondsPerYear`) |
| `pmdec_mas_per_year` | double | mu_delta in mas/yr |
| `ra_apparent_deg`, `dec_apparent_deg` | double | geocentric apparent place of date (proper motion, annual aberration, light deflection, IAU 2006 precession, IAU 2000A nutation) |
| `az_deg`, `alt_deg` | double | topocentric, geometric (see "Read this first" 3) |
| `alt_refracted_deg` | double or null | Skyfield `altaz(temperature_C=10, pressure_mbar=1010)`; **null where `alt_deg < -1`** (117 of 240 cases) |

Skyfield's refraction: it iterates `alt_obs = alt + r(alt_obs)` with
`r(h) = 0.016667 deg / tan((h + 7.31/(h + 4.4)) deg) * 0.28 * P / (T + 273)` (Bennett's
formula evaluated at the *observed* altitude `h`, P in mbar, T in Celsius) until the change is
below 3e-5 deg, and applies nothing for an observed altitude below -1 deg or above 89.9 deg.
The pressure is the explicit 1010 mbar, not an elevation-based estimate. Saemundsson's formula
(true altitude, 1.02' / tan(h + 10.3/(h + 5.11))) differs from it by at most 0.07' (0.0011 deg)
for true altitudes between -0.5 and 85 deg, and by 0.48' at -1 deg; compare refracted
altitudes only above the horizon.

## bodies_apparent.json

Top level: `sites` (6), `cases` (450 = 50 instants x 9 bodies). The instants are
2000-01-01T12:00:00Z, 2026-10-17T00:00:00Z and 48 seeded ones over 1950-2049; instant `i`
(0-based, ascending) is observed from site `i mod 6`, and all nine bodies share it. Bodies, in
order: `sun`, `moon`, `mercury`, `venus`, `mars`, `jupiter`, `saturn`, `uranus`, `neptune`.
Mars, Jupiter, Saturn, Uranus and Neptune are the system barycentres (DE440s has no body-centre
segments for them); the offset from the planet centre is at most 0.07 arcsec (0.01 arcsec for
Jupiter on 2026-10-17).

| Field | Type | Definition |
| --- | --- | --- |
| `utc`, `ut1_jd`, `tt_jd`, `site`, `lat`, `lon`, `elevation_m` | | instant and observer |
| `body` | string | one of the nine names above |
| `ra_apparent_j2000_deg`, `dec_apparent_j2000_deg` | double | geocentric apparent direction on the ICRS (J2000) axes: light time, light deflection, annual aberration. With `distance_au` this is the vector `BodyState.geocentricJ2000` should reproduce. For the Moon and Sun it equals the geocentric vector with both bodies at `t - light time` and no separate aberration (0.0005 arcsec), as DESIGN.md prescribes for the Moon |
| `ra_apparent_deg`, `dec_apparent_deg` | double | the same direction in the true equator and equinox of date |
| `ra_topo_deg`, `dec_topo_deg` | double | topocentric apparent place of date (parallax, diurnal aberration included) |
| `distance_au` | double | geocentric distance, light-time corrected (the length of the astrometric vector) |
| `az_deg`, `alt_deg` | double | topocentric geometric horizontal coordinates of the body's centre |
| `illuminated_fraction` | double or null | `(1 + cos(phase_angle_deg)) / 2`; null for the Sun |
| `phase_angle_deg` | double or null | geocentric Sun-body-Earth angle at the body, 0 = full (Skyfield `phase_angle`; the Sun's position is taken at the observation instant); null for the Sun |
| `elongation_deg` | double or null | angle between the geocentric apparent directions of the body and the Sun; null for the Sun |
| `heliocentric_distance_au` | double or null | planets only: Sun-planet distance with both bodies at the instant the light left the planet (observation time minus light time) |
| `apparent_magnitude` | double or null | planets only: Mallama and Hilton (2018), Skyfield `magnitudelib`; null if the model returns NaN (none do here) |

## riseset.json

Top level: `sites` (5), `cases` (30): five sites x six dates (2026-01-15, 2026-03-20,
2026-06-21, 2026-10-17, 2026-12-21, 2030-08-01), including midnight-sun and polar-night windows
at `tromso`.

Each case: `site`, `lat`, `lon`, `elevation_m`, `date`, `window_start_utc`, `window_end_utc`
and `objects`. The window is **local noon of `date` to the next local noon, where local noon is
12:00:00 UT minus `lon`/15 hours, rounded to whole seconds** (so `boulder` windows start
at 19:01:05Z). Events are searched strictly inside it.

`objects` has the keys `sun`, `moon`, `jupiter`, `venus`, `sirius`, `vega` (the two stars with
the `stars_apparent.json` inputs). Each object record has:

* `horizon`: a *crossing list* (below) for the object's rise/set threshold;
* `horizon_upper_limb`: Moon only (see "Read this first" 2);
* `civil`, `nautical`, `astronomical`: Sun only, crossing lists for -6, -12 and -18 deg;
* `transits`: `[{utc, unix, altitude_deg}]`.

A *crossing list* is `{h0_deg, crossings, always_up, always_down}`. `crossings` holds every
instant in the window where `topocentric geometric altitude of the centre - h0` changes sign,
as `{kind, utc, unix}` (`kind` is `rise` for an upward crossing and `set` for a downward one;
for the twilight lists these are dawn and dusk). If it is empty, exactly one of `always_up`
and `always_down` is true (the altitude stays at least 0.05 deg from `h0` all window long);
otherwise both are false. `h0_deg` is -0.5667 for stars and planets, -0.8333 for the Sun,
-6/-12/-18 for the twilights and **null for the Moon**, whose `h0` varies: each Moon crossing
carries its own `h0_deg`.

`transits` are the local maxima of the topocentric geometric altitude (upper culminations)
inside the window, with that altitude, found with `find_maxima` to 10 ms. They are not meridian
passages: for a fixed star the two coincide (0.02 s); for the Sun they differ by up to about a
minute (the US Naval Observatory comparison, whole minutes, shows -51..+45 s); for the Moon by
many minutes at high latitude (up to 11.6 minutes at `tromso`, where the Moon's altitude is
flat near culmination).
Culminations below the horizon are listed (negative altitude). Every window of this data set
holds exactly one transit per object.

Example (`boulder`, 2026-10-17, window `2026-10-17T19:01:05Z` to `2026-10-18T19:01:05Z`):

```json
"moon": {
  "horizon": {"h0_deg": null, "crossings": [
    {"kind": "rise", "utc": "2026-10-17T20:07:10.599Z", "unix": 1792267630.599, "h0_deg": 0.091088},
    {"kind": "set", "utc": "2026-10-18T05:02:57.415Z", "unix": 1792299777.415, "h0_deg": 0.091917}],
    "always_up": false, "always_down": false},
  "horizon_upper_limb": {"h0_deg": null, "crossings": [
    {"kind": "rise", "utc": "2026-10-17T20:01:13.385Z", "unix": 1792267273.385, "h0_deg": -0.812967},
    {"kind": "set", "utc": "2026-10-18T05:08:54.905Z", "unix": 1792300134.905, "h0_deg": -0.813285}],
    "always_up": false, "always_down": false},
  "transits": [{"utc": "2026-10-18T00:35:07.528Z", "unix": 1792283707.528, "altitude_deg": 23.596667722}]}
```

Cases worth testing: `tromso` 2026-06-21 (Sun `always_up` for all four lists), `tromso`
2026-12-21 (Sun `horizon` `always_down`, twilights with crossings; Moon `always_up`), `quito`
2026-03-20 (Sun transit at 89.957 deg, a near-zenith maximum), and the 5 Moon windows with a
single crossing (the Moon rises or sets only once).

## moon_phases.json

* `phases[]` (248): every principal phase with 2024-01-01 <= instant < 2029-01-01, as
  `{phase, utc, unix}` where `phase` is `new`, `first_quarter`, `full` or `last_quarter`. They
  are the instants where the geocentric apparent ecliptic longitude of the Moon minus that of
  the Sun, in the true ecliptic of date, is 0, 90, 180, 270 degrees (`skyfield.almanac.moon_phases`),
  resolved to 1 ms; `utc` is the instant read as UT1. The first is a last quarter on
  2024-01-04, the last a full moon on 2028-12-31.
* `samples[]` (30 seeded instants over 2024-2028): `utc`, `ut1_jd`, `tt_jd`, then
  `illuminated_fraction` and `phase_angle_deg` (geocentric; same definitions as in
  `bodies_apparent.json`), `ecliptic_elongation_deg` (Skyfield `almanac.moon_phase`: Moon minus
  Sun apparent ecliptic longitude in [0, 360), 0 new, 90 first quarter, 180 full, 270 last
  quarter; the Moon is waxing while it is below 180) and `age_days` (days since the preceding
  new moon in the full list; the search starts one lunation before 2024).

## Writing tests against the fixtures

Differences that are legitimate consequences of model choices, measured on these fixtures
(1950-2049) with ERFA/SOFA, so that tolerances can be set with their cause in mind:

| If the implementation ... | the result moves by (at most) |
| --- | --- |
| uses IAU 1976 precession and IAU 1980 nutation instead of IAU 2006/2000A | 0.15 arcsec in a star's apparent place (median 0.04) |
| uses IAU 1976 instead of IAU 2006 precession (rotation angle of the matrix) | 0.15 arcsec |
| uses the IAU 1980 nutation series | 0.015 arcsec in longitude, 0.007 arcsec in obliquity |
| uses the IAU 1976 mean obliquity | 0.053 arcsec |
| computes GMST with the IAU 1982 formula (Meeus 12.4) | 0.0097 s of time (0.15 arcsec) |
| uses the IAU 1994 equation of the equinoxes | 0.014 arcsec |
| omits gravitational light deflection | 0.015 arcsec for these stars (1.75 arcsec at the solar limb) |
| omits diurnal aberration | 0.32 arcsec in `az_deg`/`alt_deg` (median 0.18) |
| ignores proper motion | up to 85 arcsec (Arcturus, 43 years before J2000) |
| uses Saemundsson instead of Skyfield's refraction | 0.07' for true altitudes -0.5..85 deg |
| uses a Delta T that is too large by 1 s | 0.55 arcsec for the Moon, 0.04 arcsec for the Sun |

Rise/set times scale with position error: near the horizon the altitude of a rising or setting
body changes by 11-15 arcsec per second of time at low and mid latitudes, so a 30 arcsec error
moves a crossing by 2-3 s; windows at high latitude are far more sensitive.

Suggested use per file:

* `sidereal.json`: `SiderealTime`, `Obliquity`, `Nutation`, `Precession`, `Aberration.earthVelocity`
  and `JulianDate.deltaT(decimalYear:)` (compare with `delta_t_seconds`, expecting the
  differences discussed above for the model in use).
* `stars_apparent.json`: `SkyFrame.apparentPlace` and `SkyFrame.horizontal`, with and without
  refraction, one `SkyFrame` per `(utc, site)`.
* `bodies_apparent.json`: first the ephemeris (`geocentricJ2000` against the `..._j2000_deg`
  pair and `distance_au`, phase, elongation, magnitude), then `SkyFrame.topocentricEquatorial`
  and `horizontal` with the J2000 vector the *fixture* provides, which isolates the frame code
  from the ephemeris error.
* `riseset.json`: `RiseSetCalculator` with the window from the file. For
  `TwilightCalculator.night(startingOn:observer:timeZone:)`, whose night runs from the time
  zone's local noon, use `TimeZone(secondsFromGMT: Int((lon * 240).rounded()))`: local noon is then
  exactly `window_start_utc`.
* `moon_phases.json`: the next-phase function (the phases are contiguous, so for any instant
  between two entries the next phase is known) and the illumination, phase-angle and age
  functions with `samples`.

## Validation

Every generation cross-checks the rise/set results; `--external-check` compares the written
fixtures with two public services (so its numbers can move slightly when the services change).
The ERFA and transit checks were run once with throw-away scripts. Results of the last run
(reproduce the service comparisons with `python -I Tools/make_fixtures.py --external-check`):

| Check | Result |
| --- | --- |
| `sidereal.json` (all 44 instants) vs ERFA/SOFA 2.0.1.5 (`gmst06`, `gst06a`, `nut00a`, `obl06`, `bp06`, `numat`, `epv00`) | GMST 2e-7 s, GAST 2e-6 s, nutation 5e-7 arcsec, mean obliquity 2e-6 arcsec, matrix elements 1e-7 arcsec, Earth beta 8e-12 (ad hoc script, not in the repository) |
| `stars_apparent.json` (all 240 cases) vs ERFA/SOFA 2.0.1.5 (`apci13`/`atciq` for the apparent place; `apco`/`atciq`/`atioq` with `epv00`, `xy06`, `s06`, `era00`, `sp00` for az/alt) | apparent place of date: 2.1e-5 arcsec max; az/alt: 4e-4 arcsec max (ad hoc script, not in the repository) |
| Moon and Mars apparent RA/Dec vs JPL Horizons quantity 2, geocentric, same TT, 1955-2043 | 0.084 arcsec max in RA, 0.011 in Dec |
| Same, topocentric from Boulder, 2026-10-17 | 0.063 arcsec max |
| All 450 `bodies_apparent.json` entries vs Horizons, geocentric, same TT | RA 0.084 arcsec, Dec 0.029 arcsec max; `distance_au` 7.9e-11 AU max; `heliocentric_distance_au` 1.6e-6 AU max (Horizons uses the Sun at the observation time); `illuminated_fraction` 0.009 percentage points; `elongation_deg` 1.1e-4 deg; `phase_angle_deg` 0.0115 deg; `apparent_magnitude` 0.135 (Mercury), 0.116 (Mars), at most 0.03 for the others |
| Rise/set vs Skyfield's own `find_risings`/`find_settings`/`find_transits` (all 30 windows) | 0.034 s max; fixed-star transits 0.021 s |
| All 180 transits, sampled every 0.25 s from -3 s to +3 s | each is the altitude maximum; reported altitude reproduced to 5e-10 deg (ad hoc script) |
| 2026-10-17 rise/set vs Horizons 1-minute RTS search (boulder, sydney, tromso; Sun, Moon, Jupiter, Venus) | Sun and planets and `moon.horizon_upper_limb`: Horizons time minus fixture within -1.8..+54 s (a Horizons event lies in the minute before its printed time); `moon.horizon`: -311..+363 s |
| Rise/set vs US Naval Observatory (60 daily queries) | Sun rise/set -52..+33 s (n=56); civil twilight -29..+28 s (56); `moon.horizon_upper_limb` -30..+28 s (49); `moon.horizon` -957..+951 s (48); USNO prints whole minutes |
| Moon phases vs US Naval Observatory (all 248) | -20.8..+41.2 s |
| Determinism | two full runs, and runs with different BLAS thread counts, produced byte-identical files |

The constant 0.04-0.08 arcsec offset in right ascension against Horizons is its documented
choice of equinox: "equinox (RA origin) is offset -53 mas from the of-date frame defined by the
IAU06/00a P & N system". Declinations agree to 0.03 arcsec.

## Regenerating

```sh
# once: an environment with numpy (system package or `pip install numpy`), then the pinned set
python3 -m venv --system-site-packages .venv-fixtures
.venv-fixtures/bin/pip install --require-hashes -r Tools/requirements-fixtures.txt

# regenerate every file (about 70 s); the first run downloads de440s.bsp (31 MiB)
.venv-fixtures/bin/python -I Tools/make_fixtures.py [--data-dir DIR] [--out-dir DIR]

# compare the written files with JPL Horizons and the US Naval Observatory (about 1 min)
.venv-fixtures/bin/python -I Tools/make_fixtures.py --external-check
```

Python 3.10 or newer. `-I` makes the interpreter ignore the environment and the working
directory while it reads downloaded data. `--data-dir` defaults to
`$XDG_CACHE_HOME/lodestar-fixtures` (`~/.cache/lodestar-fixtures`), `--out-dir` to this
directory. (On Debian without `python3-venv`, use `virtualenv --system-site-packages`.)

Pinned inputs:

* `de440s.bsp` from `https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp`,
  32,726,016 bytes, SHA-256 `c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2`
  (also identical on the JPL SSD mirror; NAIF's published MD5 `3917ee56769db332790c751e2168843d`
  matches). The script checks size and hash after the download and again before every use.
* Skyfield 1.55, jplephem 2.24, sgp4 2.27, certifi 2026.7.22, each with SHA-256 hashes
  (`Tools/requirements-fixtures.txt`). Time scale: Skyfield's built-in tables only (no IERS
  download; the data span IERS daily values from 1973-01-02 to 2027-01-23).
* Star data: embedded in the script with its provenance (Hipparcos via VizieR I/239/hip_main,
  retrieved 2026-10-17).
* Sampling: `random.Random(20261017 + k)`, `k` = 1 (sidereal), 2 (stars), 3 (bodies),
  5 (moon-phase samples); one instant per equal stratum of 1950-2049 (or 2024-2028), whole
  seconds. Identical library versions give identical files on one platform; another platform
  or Skyfield version may flip last rounded digits or, with updated Delta T tables, change
  `delta_t_seconds` after 2027.

Nothing downloaded is executed or unpickled; the ephemeris is read as data by `jplephem`.

## Known limitations

* Positions are DE440s (Horizons used DE441 in the checks above); DE440s covers
  1849-12-25 through 2150-01-21.
* Delta T after 2027-01-23 is Skyfield's extrapolation (69-71 s through 2049); UT1 is taken as
  the calendar value, so these fixtures say nothing about DUT1.
* The star inputs are catalogue values, not a statement about the best current astrometry
  (Gaia); they only have to be identical on both sides of a comparison.
* Polar motion (below 0.3 arcsec) and the atmosphere other than the refraction field are not
  modelled; `alt_refracted_deg` uses a fixed 1010 mbar and 10 C.
* Skyfield moves a star in a straight line in space (distance 1 Gpc when the parallax is
  zero). Propagating the proper motion linearly in right ascension and declination instead
  differs by less than 0.01 arcsec at the instants of `stars_apparent.json` (Arcturus, 43 years
  from J2000, is the worst case).

## Satellite fixtures (`Tools/make_satellite_fixtures.py`)

| File | Contents |
| --- | --- |
| `sgp4_ver.tle`, `sgp4_tcppver.out` | SGP4 verification element sets and the C++ reference output (Vallado et al. 2006, CelesTrak) |
| `satellite_omm_sample.json`, `satellite_stations.json`, `satellite_stations.tle`, `satellite_starlink_sample.json` | CelesTrak GP snapshots (OMM JSON and TLE) taken 2026-10-18 |
| `satellite_reference.json` | Skyfield 1.55 + DE421 passes, looks and shadow transitions for several sites |
| `satellite_streaks.json` | Skyfield frame crossings for a 2,976-satellite constellation |

## Provenance and licences

Skyfield (MIT licence, Brandon Rhodes), JPL DE440s (public domain, Park et al. 2021, NASA/JPL),
Hipparcos catalogue (ESA 1997, distributed by CDS VizieR), JPL Horizons and US Naval Observatory
API (public services, used only for validation). The JSON files contain derived numbers only.
