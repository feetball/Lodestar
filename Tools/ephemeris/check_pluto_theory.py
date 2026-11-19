"""Check Meeus chapter 37's Pluto series (pluto_tables.py) against Meeus's example and JPL's DE440s.

Usage: python -I check_pluto_theory.py [path to de440s.bsp] [--json]

Needs numpy and Skyfield (the repository's fixture tool, Tools/make_fixtures.py, uses the same versions) and the JPL
DE440s kernel (default: ~/.cache/lodestar-fixtures/de440s.bsp, the cache directory of make_fixtures.py). Prints

  (a) Example 37.a (1992 October 13.0 TT) against the book's values,
  (b) the error of the heliocentric ecliptic J2000 longitude (times cos latitude), latitude and radius against DE440s's
      Pluto-system barycentre minus the Sun, sampled every 10 days over 1885-2099 (the stated validity) and over
      1850-1884 and 2100-2149 (outside it),
  (c) the error of the apparent geocentric direction over 1950-2049, built like Ephemeris.swift builds it (the series
      at the instant the light left Pluto, minus the Earth's heliocentric position) against Skyfield's astrometric
      direction with its own light-time iteration,
  (d) ranges: heliocentric and geocentric distance and the largest geocentric ecliptic latitude over 1850-2150, the
      bound of the series for any date, and the radius for the years that Ephemeris's far-time test uses.

The series is evaluated with the same formulas and the same order of operations that PlutoTheory.swift and
PlutoTheory.kt use (see gen_pluto_theory.py), here with NumPy arrays.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import pluto_tables as tables  # noqa: E402
from skyfield import framelib  # noqa: E402
from skyfield.api import load  # noqa: E402
from skyfield.jpllib import SpiceKernel  # noqa: E402

J2000 = 2451545.0
DAYS_PER_CENTURY = 36525.0
ARCSEC_PER_RADIAN = 180 * 3600 / math.pi
# Ephemeris.lightTimePerAU: kilometres per AU / speed of light / seconds per day (days per AU).
LIGHT_TIME_PER_AU = 149_597_870.7 / 299_792.458 / 86_400.0
OBLIQUITY_J2000 = 23.0 + 26.0 / 60 + 21.448 / 3600
MULTIPLIERS = np.array([row[0:3] for row in tables.TABLE], dtype=float)
LONGITUDE = np.array([row[3:5] for row in tables.TABLE], dtype=float)
LATITUDE = np.array([row[5:7] for row in tables.TABLE], dtype=float)
RADIUS = np.array([row[7:9] for row in tables.TABLE], dtype=float)


def series(jd_tt):
    """Heliocentric ecliptic J2000 (longitude deg [0, 360), latitude deg, radius AU) for arrays of JDE."""
    t = (np.asarray(jd_tt, dtype=float) - J2000) / DAYS_PER_CENTURY
    j = tables.J_MEAN[0] + tables.J_MEAN[1] * t
    s = tables.S_MEAN[0] + tables.S_MEAN[1] * t
    p = tables.P_MEAN[0] + tables.P_MEAN[1] * t
    sum_l = np.zeros_like(t)
    sum_b = np.zeros_like(t)
    sum_r = np.zeros_like(t)
    for n in range(len(tables.TABLE)):
        argument = MULTIPLIERS[n, 0] * j + MULTIPLIERS[n, 1] * s + MULTIPLIERS[n, 2] * p
        sine = np.sin(np.radians(argument))
        cosine = np.cos(np.radians(argument))
        sum_l += LONGITUDE[n, 0] * sine + LONGITUDE[n, 1] * cosine
        sum_b += LATITUDE[n, 0] * sine + LATITUDE[n, 1] * cosine
        sum_r += RADIUS[n, 0] * sine + RADIUS[n, 1] * cosine
    longitude = np.mod(tables.LONGITUDE_MEAN[0] + tables.LONGITUDE_MEAN[1] * t + sum_l / 1e6, 360.0)
    latitude = tables.LATITUDE_MEAN + sum_b / 1e6
    radius = tables.RADIUS_MEAN + sum_r / 1e7
    return longitude, latitude, radius


def to_vector_j2000(longitude, latitude, radius):
    """Ecliptic spherical (degrees, AU) to a (3, N) array in the mean equatorial frame of J2000.0."""
    lon, lat = np.radians(longitude), np.radians(latitude)
    x = radius * np.cos(lat) * np.cos(lon)
    y = radius * np.cos(lat) * np.sin(lon)
    z = radius * np.sin(lat)
    eps = math.radians(OBLIQUITY_J2000)
    return np.array([x, y * math.cos(eps) - z * math.sin(eps), y * math.sin(eps) + z * math.cos(eps)])


def amplitude_bound():
    """Largest possible |sum| for l (deg), b (deg) and r (AU): the sum of sqrt(A^2 + B^2) over the rows."""
    return tuple(float(np.sum(np.hypot(c[:, 0], c[:, 1]))) / scale for c, scale in
                 ((LONGITUDE, 1e6), (LATITUDE, 1e6), (RADIUS, 1e7)))


def julian_day(year, month, day):
    """Julian day of a calendar date (Meeus ch. 7; Gregorian from 1582 October 15, Julian before)."""
    if month <= 2:
        year, month = year - 1, month + 12
    a = year // 100
    b = 2 - a + a // 4 if (year, month, day) >= (1582, 10, 15) else 0
    return math.floor(365.25 * (year + 4716)) + math.floor(30.6001 * (month + 1)) + day + b - 1524.5


class Reference:
    """DE440s through Skyfield: Pluto-system barycentre, the Sun and the Earth in ICRS."""

    def __init__(self, path):
        self.kernel = SpiceKernel(path)
        self.ts = load.timescale()
        self.rotation = framelib.ecliptic_J2000_frame.rotation_at(None)  # constant ICRS -> ecliptic J2000
        self.pluto = self.kernel["pluto barycenter"]
        self.sun = self.kernel["sun"]
        self.earth = self.kernel["earth"]

    def time(self, jd_tt):
        return self.ts.tt_jd(np.asarray(jd_tt, dtype=float))

    def pluto_heliocentric(self, jd_tt):
        t = self.time(jd_tt)
        return self.pluto.at(t).position.au - self.sun.at(t).position.au

    def earth_heliocentric(self, jd_tt):
        t = self.time(jd_tt)
        return self.earth.at(t).position.au - self.sun.at(t).position.au

    def astrometric_from_earth(self, jd_tt):
        """Skyfield's geocentric astrometric vector to Pluto (light-time iterated), ICRS AU."""
        t = self.time(jd_tt)
        return self.earth.at(t).observe(self.pluto).position.au


def to_ecliptic(vector, rotation):
    ecliptic = rotation @ vector
    radius = np.sqrt(np.sum(ecliptic ** 2, axis=0))
    return (np.degrees(np.arctan2(ecliptic[1], ecliptic[0])) % 360.0,
            np.degrees(np.arcsin(ecliptic[2] / radius)), radius)


def sample(first_jd, last_jd, step):
    return np.arange(first_jd, last_jd + 1e-9, step)


def heliocentric_errors(reference, first_jd, last_jd, step=10.0):
    jd = sample(first_jd, last_jd, step)
    lon_ref, lat_ref, r_ref = to_ecliptic(reference.pluto_heliocentric(jd), reference.rotation)
    lon, lat, r = series(jd)
    d_lon = (lon - lon_ref + 180.0) % 360.0 - 180.0
    lon_error = np.abs(d_lon * np.cos(np.radians(lat_ref))) * 3600.0
    lat_error = np.abs(lat - lat_ref) * 3600.0
    radius_error = np.abs(r - r_ref) / r_ref
    worst = int(np.argmax(lon_error))
    return {
        "samples": int(len(jd)),
        "lon_cos_lat_arcsec_max": float(lon_error.max()),
        "lon_cos_lat_arcsec_rms": float(np.sqrt(np.mean(lon_error ** 2))),
        "lon_max_at_jd": float(jd[worst]),
        "lat_arcsec_max": float(lat_error.max()),
        "lat_arcsec_rms": float(np.sqrt(np.mean(lat_error ** 2))),
        "radius_rel_max": float(radius_error.max()),
        "radius_abs_au_max": float(np.max(np.abs(r - r_ref))),
        "radius_rel_rms": float(np.sqrt(np.mean(radius_error ** 2))),
    }


def app_geometric(reference, jd_tt):
    """Geocentric vector the way Ephemeris.planetGeometry builds it: the planet's heliocentric position when the
    light left it minus the Earth's heliocentric position now (four light-time passes at most)."""
    earth = reference.earth_heliocentric(jd_tt)
    light_time = np.zeros_like(jd_tt)
    for _ in range(4):
        position = to_vector_j2000(*series(jd_tt - light_time))
        updated = np.sqrt(np.sum((position - earth) ** 2, axis=0)) * LIGHT_TIME_PER_AU
        converged = np.all(np.abs(updated - light_time) < 2e-6)
        light_time = updated
        if converged:
            break
    return position - earth


def angle_arcsec(a, b):
    cross = np.cross(a.T, b.T)
    dot = np.sum(a * b, axis=0)
    return np.arctan2(np.linalg.norm(cross, axis=1), dot) * ARCSEC_PER_RADIAN


def apparent_errors(reference, first_jd, last_jd, step=5.0):
    jd = sample(first_jd, last_jd, step)
    ours = app_geometric(reference, jd)
    theirs = reference.astrometric_from_earth(jd)
    separation = angle_arcsec(ours, theirs)
    distance_ours = np.sqrt(np.sum(ours ** 2, axis=0))
    distance_theirs = np.sqrt(np.sum(theirs ** 2, axis=0))
    relative = np.abs(distance_ours - distance_theirs) / distance_theirs
    return {
        "samples": int(len(jd)),
        "arcsec_max": float(separation.max()),
        "arcsec_median": float(np.median(separation)),
        "arcsec_p95": float(np.percentile(separation, 95)),
        "distance_rel_max": float(relative.max()),
        "distance_abs_au_max": float(np.max(np.abs(distance_ours - distance_theirs))),
    }


def ranges(reference):
    jd = sample(julian_day(1850, 1, 1), julian_day(2149, 12, 31), 5.0)
    _, _, r = series(jd)
    _, _, r_ref = to_ecliptic(reference.pluto_heliocentric(jd), reference.rotation)
    geocentric = to_ecliptic(app_geometric(reference, jd), reference.rotation)
    bound = amplitude_bound()
    far = {}
    for year in (-2000, -1000, 0, 1000, 1800, 2200, 3000, 4000):
        far[str(year)] = float(series(np.array([julian_day(year, 6, 1)]))[2][0])
    return {
        "r_min": float(r.min()), "r_max": float(r.max()),
        "r_min_de440s": float(r_ref.min()), "r_max_de440s": float(r_ref.max()),
        "delta_min": float(geocentric[2].min()), "delta_max": float(geocentric[2].max()),
        "max_abs_geocentric_ecliptic_latitude_deg": float(np.abs(geocentric[1]).max()),
        "max_abs_heliocentric_ecliptic_latitude_deg": float(np.abs(series(jd)[1]).max()),
        "series_bound_any_date": {
            "r_min": tables.RADIUS_MEAN - bound[2], "r_max": tables.RADIUS_MEAN + bound[2],
            "latitude_abs_max_deg": abs(tables.LATITUDE_MEAN) + bound[1],
        },
        "far_years_r": far,
    }


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = arguments[0] if arguments else os.path.expanduser("~/.cache/lodestar-fixtures/de440s.bsp")
    reference = Reference(path)
    result = {}

    longitude, latitude, radius = (float(v[0]) for v in series([tables.EXAMPLE_37A_JDE]))
    result["example_37a"] = {
        "computed": {"l": round(longitude, 5), "b": round(latitude, 5), "r": round(radius, 6)},
        "expected": {"l": tables.EXAMPLE_37A_LONGITUDE, "b": tables.EXAMPLE_37A_LATITUDE,
                     "r": tables.EXAMPLE_37A_RADIUS},
        "unrounded": {"l": longitude, "b": latitude, "r": radius},
    }
    assert result["example_37a"]["computed"] == result["example_37a"]["expected"], result["example_37a"]

    result["heliocentric_1885_2099"] = heliocentric_errors(
        reference, julian_day(1885, 1, 1), julian_day(2099, 12, 31))
    result["heliocentric_1850_1884"] = heliocentric_errors(
        reference, julian_day(1850, 1, 1), julian_day(1884, 12, 31))
    result["heliocentric_2100_2149"] = heliocentric_errors(
        reference, julian_day(2100, 1, 1), julian_day(2149, 12, 31))
    result["apparent_geocentric_1950_2049"] = apparent_errors(
        reference, julian_day(1950, 1, 1), julian_day(2049, 12, 31))
    result["ranges_1850_2150"] = ranges(reference)

    if "--json" in sys.argv:
        print(json.dumps(result, indent=2))
        return
    print("(a) Example 37.a, JDE 2448908.5")
    print("   ", result["example_37a"])
    for key in ("heliocentric_1885_2099", "heliocentric_1850_1884", "heliocentric_2100_2149"):
        print(f"(b) {key}: {result[key]}")
    print(f"(c) apparent geocentric 1950-2049: {result['apparent_geocentric_1950_2049']}")
    print(f"(d) ranges: {json.dumps(result['ranges_1850_2150'], indent=2)}")


if __name__ == "__main__":
    main()
