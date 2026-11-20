#!/usr/bin/env python3
"""Reference ISS transits of the Sun and the Moon, for the SatelliteTransitFinder tests.

A brute-force search that shares no code with LodestarKit: Skyfield 1.55 (SGP4 from the ``sgp4`` package, the JPL
DE440s ephemeris, IAU 2000 frames) samples the angular separation between the ISS and the centre of the Sun or the
Moon every second over every pass above 3 degrees, refines each minimum to 1 ms, and keeps a transit when the satellite
(span 109 m) overlaps the disc or when the centreline, found by Newton iteration on the separation vector at that
moment for ground displacements, is within 50 km. The element set is the TLE of
``LodestarKit/Tests/LodestarKitTests/Fixtures/satellite_iss_transit.tle`` (CelesTrak, 2026-11-19, sha256 in the
fixtures README).

Usage (``-I`` makes the interpreter ignore the environment and the working directory)::

    python3 -m venv --without-pip VENV && pip3 --python VENV/bin/python install skyfield==1.55 jplephem numpy sgp4
    VENV/bin/python -I Tools/make_satellite_transit_reference.py

``de440s.bsp`` is read from ``~/.cache/lodestar-fixtures`` (download it with ``Tools/make_fixtures.py``, which pins
its SHA-256). The output of the committed fixture is quoted in ``SatelliteTransitFinderTests``.
"""

from pathlib import Path

import numpy as np
from skyfield.api import load, wgs84, EarthSatellite

TLE_FILE = Path(__file__).resolve().parent.parent / "LodestarKit/Tests/LodestarKitTests/Fixtures/satellite_iss_transit.tle"
_lines = TLE_FILE.read_text().splitlines()
TLE1, TLE2 = _lines[1], _lines[2]
LAT, LON, ELEV = 40.015, -105.2705, 1655.0
START = (2026, 11, 19, 17, 0, 0)
DAYS = 14
RADII = {"sun": 695700.0, "moon": 1737.4}
SPAN_M = 109.0
MAX_GROUND_KM = 50.0

ts = load.timescale()
eph = load(str(Path.home() / ".cache/lodestar-fixtures/de440s.bsp"))
earth = eph["earth"]
bodies = {"sun": eph["sun"], "moon": eph["moon"]}
sat = EarthSatellite(TLE1, TLE2, "ISS", ts)


def unit(v):
    return v / np.linalg.norm(v, axis=0)


def site(lat, lon):
    return wgs84.latlon(lat, lon, elevation_m=ELEV)


def directions(lat, lon, t, name):
    topos = site(lat, lon)
    s = (sat - topos).at(t).position.km          # satellite, topocentric (geometric)
    b = (earth + topos).at(t).observe(bodies[name]).apparent().position.km
    return s, b


def separation_deg(lat, lon, t, name):
    s, b = directions(lat, lon, t, name)
    c = np.sum(unit(s) * unit(b), axis=0)
    return np.degrees(np.arccos(np.clip(c, -1, 1)))


def offsets(lat, lon, t, name):
    s, b = directions(lat, lon, t, name)
    bu, su = unit(b), unit(s)
    pole = np.array([0.0, 0.0, 1.0])
    e1 = np.cross(pole, bu)
    e1 = e1 / np.linalg.norm(e1)
    e2 = np.cross(bu, e1)
    dot = float(np.dot(su, bu))
    return np.array([np.degrees(np.arctan2(np.dot(su, e1), dot)), np.degrees(np.arctan2(np.dot(su, e2), dot))])


def metres_per_degree(lat):
    a, f = 6378137.0, 1 / 298.257223563
    e2 = f * (2 - f)
    s = np.sin(np.radians(lat))
    w = 1 - e2 * s * s
    return a * (1 - e2) / w ** 1.5 * np.pi / 180, a / np.sqrt(w) * np.cos(np.radians(lat)) * np.pi / 180


def centreline(t, name):
    lat, lon = LAT, LON
    for _ in range(4):
        f0 = offsets(lat, lon, t, name)
        if np.hypot(*f0) < 1e-7:
            break
        mlat, mlon = metres_per_degree(lat)
        h = 1000.0
        cols = []
        for dn, de in ((0, h), (h, 0)):
            fp = offsets(lat + dn / mlat, lon + de / mlon, t, name)
            fm = offsets(lat - dn / mlat, lon - de / mlon, t, name)
            cols.append((fp - fm) / (2 * h))
        jac = np.column_stack(cols)   # columns: d/dEast, d/dNorth
        step = np.linalg.solve(jac, -f0)
        lon += step[0] / mlon
        lat += step[1] / mlat
    mlat, mlon = metres_per_degree(LAT)
    north = (lat - LAT) * mlat
    east = (lon - LON) * mlon
    dist = float(np.hypot(north, east))
    bearing = float(np.degrees(np.arctan2(east, north)) % 360)
    return lat, lon, dist, bearing, float(np.hypot(*offsets(lat, lon, t, name)))


t0 = ts.utc(*START)
t1 = ts.utc(START[0], START[1], START[2] + DAYS, START[3], START[4], START[5])
topos = site(LAT, LON)
times, events = sat.find_events(topos, t0, t1, altitude_degrees=3.0)
passes = []
rise = None
for tt, ev in zip(times, events):
    if ev == 0:
        rise = tt
    elif ev == 2 and rise is not None:
        passes.append((rise, tt))
        rise = None
print(f"passes above 3 deg: {len(passes)}")
rows = []
for name in ("sun", "moon"):
    for rise, sset in passes:
        n = int((sset.tt - rise.tt) * 86400) + 1
        grid = ts.tt_jd(np.linspace(rise.tt, sset.tt, n))
        alt = (earth + topos).at(grid).observe(bodies[name]).apparent().altaz()[0].degrees
        if alt.max() < 2.0:
            continue
        sep = separation_deg(LAT, LON, grid, name)
        k = int(np.argmin(sep))
        lo, hi = max(k - 1, 0), min(k + 1, n - 1)
        fine = ts.tt_jd(np.linspace(grid.tt[lo], grid.tt[hi], 2001))
        fsep = separation_deg(LAT, LON, fine, name)
        j = int(np.argmin(fsep))
        tmin = fine[j]
        balt = (earth + topos).at(tmin).observe(bodies[name]).apparent().altaz()[0].degrees
        if balt < 3.0:
            continue
        dist_body = np.linalg.norm((earth + topos).at(tmin).observe(bodies[name]).apparent().position.km)
        radius = np.degrees(np.arcsin(RADII[name] / dist_body))
        srange = np.linalg.norm((sat - topos).at(tmin).position.km)
        sat_radius = np.degrees(0.5 * SPAN_M / 1000 / srange)
        from_site = fsep[j] < radius + sat_radius
        reach = np.degrees(np.arctan2(MAX_GROUND_KM, max(srange - MAX_GROUND_KM, 0.2 * srange))) + 0.02
        if not from_site and fsep[j] > radius + sat_radius + reach:
            continue
        lat, lon, dist, bearing, residual = centreline(tmin, name)
        if not from_site and (dist > MAX_GROUND_KM * 1000 or residual > 0.01):
            continue
        rows.append((tmin.utc_datetime(), name, fsep[j], from_site, radius, balt, dist, bearing, lat, lon, srange))
rows.sort()
for r in rows:
    print(f"{r[0].strftime('%Y-%m-%dT%H:%M:%S.%f')[:-4]}Z {r[1]:5s} sep={r[2]:.4f} site={r[3]} r={r[4]:.4f} alt={r[5]:.2f} cl={r[6]:.1f} m @ {r[7]:.1f} ({r[8]:.5f}, {r[9]:.5f}) range={r[10]:.1f}")
