#!/usr/bin/env python3
"""Generate LodestarKit's satellite reference fixtures.

Two independent references feed the satellite tests of the Swift and Kotlin engines; both are written to
``LodestarKit/Tests/LodestarKitTests/Fixtures`` (Swift) and ``android/lodestar-kit/src/test/resources/fixtures``
(Kotlin), byte for byte the same.

``sgp4``
    The SGP4/SDP4 verification run of the reference implementation.  It downloads the C++ code of Vallado's
    "fundamentals of astrodynamics" distribution (CelesTrak ``cpp.zip``, ``SGP4.cpp`` version 2020-07-13), checks
    its SHA-256, compiles it with ``g++`` together with a driver that performs the 'v' (verification) run of the
    distribution's ``TestSGP4.cpp`` (operation mode 'i', WGS-72), and writes ``sgp4_ver.tle`` (the distribution's
    ``SGP4-VER.TLE``) and ``sgp4_tcppver.out`` (the driver's ``tcppver.out``).  The official MATLAB output of the
    2006 paper's distribution (``tmatverDec2015.out``) is compared as a cross-check: it agrees to the last printed
    digit for every satellite except 23599 after 420 minutes, where an older Lyddane rule differs by under 1 km.

``passes``
    Pass times, looks and Earth-shadow transitions computed with Skyfield (SGP4 from the ``sgp4`` package, JPL
    DE421) for element sets stored in ``satellite_omm_sample.json`` (a snapshot of CelesTrak GP data of
    2026-10-18; see ``snapshot``).  Skyfield uses its own frame code (IAU 2000 precession-nutation, TEME rotation,
    ``is_sunlit`` with the point-source Sun and a sphere of 6378.1366 km) and shares no code with LodestarKit.

``streaks``
    Camera-frame crossings of a synthetic constellation (the Starlink sample copied 24 times with shifted nodes
    and anomalies, 2976 element sets) for a few frames, computed by sampling every 0.1 s with Skyfield positions and Skyfield's ``is_sunlit``.  The frame
    geometry (gnomonic rectangle, roll) is the one documented for ``CameraFrame``, implemented here in NumPy.

``snapshot``
    Downloads the CelesTrak GP data this script samples from.  CelesTrak updates its data continuously, so a new
    snapshot yields new numbers; the committed fixtures keep the snapshot of 2026-10-18.

Usage (``-I`` makes the interpreter ignore the environment and the working directory while it reads downloaded
files)::

    python -I Tools/make_satellite_fixtures.py sgp4 --out DIR
    python -I Tools/make_satellite_fixtures.py snapshot --out DIR
    python -I Tools/make_satellite_fixtures.py passes --out DIR --python-path /path/with/skyfield
    python -I Tools/make_satellite_fixtures.py streaks --out DIR --python-path /path/with/skyfield

``passes`` needs ``pip install skyfield sgp4 numpy`` (Skyfield 1.55, sgp4 2.27 were used) and downloads
``de421.bsp`` (verified against a pinned SHA-256).  Nothing that is downloaded is executed except the pinned C++
reference, which ``sgp4`` compiles.  Sampling is deterministic.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

CPP_ZIP_URL = "https://celestrak.org/software/vallado/cpp.zip"
CPP_ZIP_SHA256 = "16276bb1e72f90efd9c94c25a83403b0e4b04977d0d5f87487685cd479cd6866"
PAPER_ZIP_URL = "https://celestrak.org/publications/AIAA/2006-6753/AIAA-2006-6753.zip"
PAPER_ZIP_SHA256 = "3642043b706c76be87cf012db3f22e04da6b80498d00f515e51879e0ffadc115"
DE421_URL = "https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de421.bsp"
DE421_SHA256 = "a20a7139da04cbc462454634918e9a9ca69127044e2cc9d4f9c16e238d2deedc"
CELESTRAK_GP = "https://celestrak.org/NORAD/elements/gp.php"

# The 'v' run of TestSGP4.cpp without its interactive prompts.
DRIVER = r"""
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SGP4.h"
extern FILE *dbgfile;
#define pi 3.14159265358979323846
int main(int argc, char** argv) {
  FILE* infile = fopen(argv[1], "r");
  FILE* outfile = fopen(argv[2], "w");
  if (!infile || !outfile) return 1;
  dbgfile = fopen("/dev/null", "w");
  char typerun = 'v', typeinput = 'e', opsmode = 'i';
  gravconsttype whichconst = wgs72;
  double rad = 180.0 / pi;
  char longstr1[130], longstr2[130], str[2];
  double ro[3], vo[3], startmfe, stopmfe, deltamin, tsince, p, a, ecc, incl, node, argp, nu, m, arglat, truelon,
         lonper, jd, jdFrac, sec;
  int year, mon, day, hr, min;
  elsetrec satrec;
  while (feof(infile) == 0) {
    satrec.classification = 'U';
    strncpy(satrec.intldesg, "          ", 11);
    satrec.ephtype = 0; satrec.elnum = 0; satrec.revnum = 0;
    do {
      if (!fgets(longstr1, 130, infile)) break;
      strncpy(str, &longstr1[0], 1); str[1] = '\0';
    } while ((strcmp(str, "#") == 0) && (feof(infile) == 0));
    if (feof(infile) == 0) {
      if (!fgets(longstr2, 130, infile)) break;
      SGP4Funcs::twoline2rv(longstr1, longstr2, typerun, typeinput, opsmode, whichconst, startmfe, stopmfe, deltamin, satrec);
      fprintf(outfile, "%s xx\n", satrec.satnum);
      SGP4Funcs::sgp4(satrec, 0.0, ro, vo);
      fprintf(outfile, " %16.8f %16.8f %16.8f %16.8f %12.9f %12.9f %12.9f\n", satrec.t, ro[0], ro[1], ro[2], vo[0], vo[1], vo[2]);
      tsince = startmfe;
      if (fabs(tsince) > 1.0e-8) tsince = tsince - deltamin;
      while ((tsince < stopmfe) && (satrec.error == 0)) {
        tsince = tsince + deltamin;
        if (tsince > stopmfe) tsince = stopmfe;
        SGP4Funcs::sgp4(satrec, tsince, ro, vo);
        if (satrec.error > 0) fprintf(outfile, "# *** error: t:= %f *** code = %3d\n", satrec.t, satrec.error);
        if (satrec.error == 0) {
          jd = satrec.jdsatepoch; jdFrac = satrec.jdsatepochF + tsince / 1440.0;
          if (jdFrac < 0.0) { jd = jd - 1.0; jdFrac = jdFrac + 1.0; }
          SGP4Funcs::invjday_SGP4(jd, jdFrac, year, mon, day, hr, min, sec);
          fprintf(outfile, " %16.8f %16.8f %16.8f %16.8f %12.9f %12.9f %12.9f", tsince, ro[0], ro[1], ro[2], vo[0], vo[1], vo[2]);
          SGP4Funcs::rv2coe_SGP4(ro, vo, satrec.mus, p, a, ecc, incl, node, argp, nu, m, arglat, truelon, lonper);
          fprintf(outfile, " %14.6f %8.6f %10.5f %10.5f %10.5f %10.5f %10.5f %5i%3i%3i %2i:%2i:%9.6f\n", a, ecc,
                  incl*rad, node*rad, argp*rad, nu*rad, m*rad, year, mon, day, hr, min, sec);
        }
      }
    }
  }
  fclose(outfile);
  return 0;
}
"""

SITES = {
    "boulder": {"latitude": 40.015, "longitude": -105.2705, "elevation": 1655.0},
    "sydney": {"latitude": -33.8688, "longitude": 151.2093, "elevation": 20.0},
    "tromso": {"latitude": 69.6492, "longitude": 18.9553, "elevation": 10.0},
}

# (id, NORAD number, group file the record comes from)
SATELLITES = [
    ("iss", 25544, "stations"),
    ("css", 48274, "stations"),
    ("hst", 20580, "visual"),
    ("starlink", 44714, "starlink"),
    ("gps", None, "gps-ops"),  # the first element set of the group
    ("molniya", 8195, "molniya"),
    ("geo", 23613, "geo"),  # TDRS 7, geosynchronous with 13 degrees inclination: hours-long passes
    ("polar", 27386, "visual"),  # ENVISAT, sun-synchronous
]

# (satellite id, site id, hours after 2026-10-18T00:00Z at which the three-day window starts)
PASS_CASES = [
    ("iss", "boulder", 4), ("css", "boulder", 4), ("hst", "boulder", 4), ("starlink", "boulder", 4),
    ("gps", "boulder", 4), ("iss", "sydney", 8), ("molniya", "sydney", 8), ("geo", "sydney", 8),
    ("polar", "tromso", 12), ("polar", "sydney", 8),
]
WINDOW_ORIGIN = dt.datetime(2026, 10, 18, 0, 0, 0, tzinfo=dt.timezone.utc)
WINDOW_DAYS = 3
MINIMUM_ALTITUDE = 10.0
DARK_SUN_ALTITUDE = -6.0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path, expected: str | None) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "lodestar-fixtures"})
    with urllib.request.urlopen(request, timeout=300) as response, open(destination, "wb") as stream:
        shutil.copyfileobj(response, stream)
    if expected is not None and sha256(destination) != expected:
        raise SystemExit(f"{url}: unexpected SHA-256 {sha256(destination)}")


# ---------------------------------------------------------------------------------------
# sgp4
# ---------------------------------------------------------------------------------------


def make_sgp4(out: Path) -> None:
    work = Path(tempfile.mkdtemp(prefix="sgp4-ref-", dir="/dev/shm" if Path("/dev/shm").is_dir() else None))
    try:
        downloads = work / "downloads"
        sources = work / "sources"
        driver = work / "driver"
        for directory in (downloads, sources, driver):
            directory.mkdir()
        cpp_zip = downloads / "cpp.zip"
        paper_zip = downloads / "paper.zip"
        download(CPP_ZIP_URL, cpp_zip, CPP_ZIP_SHA256)
        download(PAPER_ZIP_URL, paper_zip, PAPER_ZIP_SHA256)
        with zipfile.ZipFile(cpp_zip) as archive:
            for member, name in (
                ("cpp/JustCode/SGP4.cpp", "SGP4.cpp"),
                ("cpp/JustCode/SGP4.h", "SGP4.h"),
                ("cpp/TestSGP4/SGP4-VER.TLE", "SGP4-VER.TLE"),
            ):
                text = archive.read(member).replace(b"\r\n", b"\n")
                (sources / name).write_bytes(text)
        (driver / "ver.cpp").write_text(DRIVER)
        binary = work / "ver"
        subprocess.run(
            ["g++", "-O0", "-ffp-contract=off", "-I", str(sources), "-o", str(binary), str(driver / "ver.cpp"),
             str(sources / "SGP4.cpp")],
            check=True,
        )
        produced = work / "tcppver.out"
        subprocess.run([str(binary), str(sources / "SGP4-VER.TLE"), str(produced)], check=True)

        with zipfile.ZipFile(paper_zip) as archive:
            matlab = archive.read("sgp4/mat/tmatverDec2015.out").decode()
        compare_with_matlab(produced.read_text(), matlab)

        shutil.copyfile(sources / "SGP4-VER.TLE", out / "sgp4_ver.tle")
        shutil.copyfile(produced, out / "sgp4_tcppver.out")
        print("wrote sgp4_ver.tle and sgp4_tcppver.out")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def read_states(text: str) -> list[tuple[str, list[list[float]]]]:
    groups: list[tuple[str, list[list[float]]]] = []
    for line in text.splitlines():
        if line.strip().endswith("xx"):
            groups.append((line.split()[0].lstrip("0"), []))
        elif line.strip() and not line.startswith("#"):
            groups[-1][1].append([float(field) for field in line.split()[:7]])
    return groups


def compare_with_matlab(produced: str, matlab: str) -> None:
    ours, theirs = read_states(produced), read_states(matlab)
    differing = []
    for (name, rows), (other_name, other_rows) in zip(ours, theirs):
        assert name == other_name, (name, other_name)
        worst = max(
            (max(abs(a[i] - b[i]) for i in range(1, 4)) for a, b in zip(rows, other_rows)), default=0.0
        )
        if worst > 1.0e-7:
            differing.append((name, worst))
    print("satellites that differ from the official MATLAB output:", differing)
    assert [name for name, _ in differing] == ["23599"], differing


# ---------------------------------------------------------------------------------------
# snapshot
# ---------------------------------------------------------------------------------------


def fetch_cached(downloads: Path, name: str, query: str) -> bytes:
    """Returns ``downloads/name``, downloading it from CelesTrak first if it is not there.

    CelesTrak refuses (HTTP 403) to serve the same data again before it has changed (about every two hours),
    so every download is made once and kept.
    """
    path = downloads / name
    if not path.exists():
        url = f"{CELESTRAK_GP}?{query}"
        request = urllib.request.Request(url, headers={"User-Agent": "lodestar-fixtures"})
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    return path.read_bytes()


def make_snapshot(out: Path, downloads: Path) -> None:
    """Writes the fixtures that sample CelesTrak GP data (FORMAT=json and FORMAT=tle)."""
    downloads.mkdir(parents=True, exist_ok=True)
    stations = fetch_cached(downloads, "stations.json", "GROUP=stations&FORMAT=json")
    (out / "satellite_stations.json").write_bytes(stations)
    (out / "satellite_stations.tle").write_bytes(fetch_cached(downloads, "stations.tle", "GROUP=stations&FORMAT=tle"))
    groups = {
        "visual": json.loads(fetch_cached(downloads, "visual.json", "GROUP=visual&FORMAT=json")),
        "starlink": json.loads(fetch_cached(downloads, "starlink.json", "GROUP=starlink&FORMAT=json")),
        "gps-ops": json.loads(fetch_cached(downloads, "gps.json", "GROUP=gps-ops&FORMAT=json")),
        "geo": json.loads(fetch_cached(downloads, "geo.json", "GROUP=geo&FORMAT=json")),
    }
    records = {}
    for satellite_id, number, group in SATELLITES:
        if group == "molniya":
            records[satellite_id] = json.loads(
                fetch_cached(downloads, "molniya8195.json", f"CATNR={number}&FORMAT=json")
            )[0]
        elif number is None:
            records[satellite_id] = groups[group][0]
        elif group == "stations":
            records[satellite_id] = next(r for r in json.loads(stations) if r["NORAD_CAT_ID"] == number)
        else:
            records[satellite_id] = next(r for r in groups[group] if r["NORAD_CAT_ID"] == number)
    sample = [records[satellite_id] for satellite_id, _, _ in SATELLITES]
    (out / "satellite_omm_sample.json").write_text(json.dumps(sample, separators=(",", ":")) + "\n")
    starlink = sorted(groups["starlink"], key=lambda r: r["NORAD_CAT_ID"])
    chosen = starlink[::90][:124]
    (out / "satellite_starlink_sample.json").write_text(json.dumps(chosen, separators=(",", ":")) + "\n")
    print("wrote snapshots:", len(sample), "reference satellites,", len(chosen), "Starlink records")


# ---------------------------------------------------------------------------------------
# passes
# ---------------------------------------------------------------------------------------


def make_passes(out: Path, python_path: str | None, cache: Path) -> None:
    if python_path:
        sys.path.insert(0, python_path)
    import numpy as np  # noqa: F401
    import skyfield
    from skyfield.api import EarthSatellite, Loader, wgs84
    from skyfield.timelib import Time  # noqa: F401

    cache.mkdir(parents=True, exist_ok=True)
    bsp = cache / "de421.bsp"
    if not bsp.exists():
        download(DE421_URL, bsp, DE421_SHA256)
    loader = Loader(str(cache))
    eph = loader("de421.bsp")
    ts = loader.timescale(builtin=True)
    earth, sun = eph["earth"], eph["sun"]

    sample = json.loads((out / "satellite_omm_sample.json").read_text())
    by_id = {satellite_id: record for (satellite_id, _, _), record in zip(SATELLITES, sample)}
    satellites = {satellite_id: EarthSatellite.from_omm(ts, dict(record)) for satellite_id, record in by_id.items()}

    def unix(time) -> float:
        return (time.utc_datetime() - dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)).total_seconds()

    def time_at(seconds: float):
        moment = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(seconds=seconds)
        return ts.utc(moment.year, moment.month, moment.day, moment.hour, moment.minute,
                      moment.second + moment.microsecond / 1e6)

    def times_array(seconds):
        base = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
        return [base + dt.timedelta(seconds=float(s)) for s in seconds]

    def topocentric(satellite, topos, seconds: float):
        t = time_at(seconds)
        difference = (satellite - topos).at(t)
        alt, az, distance = difference.altaz()
        return t, difference, alt.degrees, az.degrees, distance.km

    def altitude(satellite, topos, seconds: float) -> float:
        return topocentric(satellite, topos, seconds)[2]

    def sun_altitude(topos, seconds: float) -> float:
        t = time_at(seconds)
        apparent = (earth + topos).at(t).observe(sun).apparent()
        return apparent.altaz()[0].degrees

    def sunlit(satellite, seconds: float) -> bool:
        return bool(satellite.at(time_at(seconds)).is_sunlit(eph))

    def bisect(predicate_low_false, low: float, high: float, tolerance: float = 0.001) -> float:
        """Smallest time in (low, high] where the predicate (false at low, true at high) holds."""
        while high - low > tolerance:
            middle = 0.5 * (low + high)
            if predicate_low_false(middle):
                high = middle
            else:
                low = middle
        return 0.5 * (low + high)

    def golden_max(function, low: float, high: float, tolerance: float = 0.001) -> float:
        ratio = (math.sqrt(5) - 1) / 2
        c, d = high - ratio * (high - low), low + ratio * (high - low)
        fc, fd = function(c), function(d)
        while high - low > tolerance:
            if fc > fd:
                high, d, fd = d, c, fc
                c = high - ratio * (high - low)
                fc = function(c)
            else:
                low, c, fc = c, d, fd
                d = low + ratio * (high - low)
                fd = function(d)
        return 0.5 * (low + high)

    cases = []
    looks = []
    for satellite_id, site_id, start_hour in PASS_CASES:
        site = SITES[site_id]
        topos = wgs84.latlon(site["latitude"], site["longitude"], site["elevation"])
        satellite = satellites[satellite_id]
        start = WINDOW_ORIGIN.timestamp() + start_hour * 3600.0
        end = start + WINDOW_DAYS * 86400
        t0, t1 = time_at(start), time_at(end)
        times, events = satellite.find_events(topos, t0, t1, altitude_degrees=MINIMUM_ALTITUDE)
        # Group rise (0), culmination (1), set (2) into passes; keep only complete passes inside the window.
        passes = []
        index = 0
        event_list = [(unix(t), int(e)) for t, e in zip(times, events)]
        while index + 2 < len(event_list):
            (tr, er), (tc, ec), (ts_, es) = event_list[index:index + 3]
            if (er, ec, es) != (0, 1, 2):
                index += 1
                continue
            index += 3
            f = lambda s: altitude(satellite, topos, s) - MINIMUM_ALTITUDE
            rise = bisect(lambda s: f(s) >= 0, tr - 5.0, tr + 5.0)
            set_ = bisect(lambda s: f(s) < 0, ts_ - 5.0, ts_ + 5.0)
            culmination = golden_max(lambda s: altitude(satellite, topos, s), tc - 20.0, tc + 20.0)
            _, _, culmination_alt, culmination_az, culmination_range = topocentric(satellite, topos, culmination)
            _, _, _, rise_az, _ = topocentric(satellite, topos, rise)
            _, _, _, set_az, _ = topocentric(satellite, topos, set_)

            def is_visible(s: float) -> bool:
                return sunlit(satellite, s) and sun_altitude(topos, s) < DARK_SUN_ALTITUDE

            visible = []
            step = max(2.0, (set_ - rise) / 600.0)
            moments = [rise + k * step for k in range(int((set_ - rise) / step) + 1)] + [set_]
            previous = is_visible(moments[0])
            previous_time = moments[0]
            interval_start = moments[0] if previous else None
            for moment in moments[1:]:
                state = is_visible(moment)
                if state != previous:
                    edge = bisect(lambda s: is_visible(s) == state, previous_time, moment)
                    if state:
                        interval_start = edge
                    else:
                        visible.append([interval_start, edge])
                previous, previous_time = state, moment
            if previous:
                visible.append([interval_start, set_])
            passes.append({
                "rise": rise, "culmination": culmination, "set": set_,
                "riseAzimuth": rise_az, "culminationAltitude": culmination_alt,
                "culminationAzimuth": culmination_az, "culminationRange": culmination_range, "setAzimuth": set_az,
                "visible": visible,
                "sunlitAtCulmination": sunlit(satellite, culmination),
                "sunAltitudeAtCulmination": sun_altitude(topos, culmination),
            })
        grid = ts.from_datetimes(times_array([start + 300.0 * k for k in range(int(WINDOW_DAYS * 288) + 1)]))
        altitudes = (satellite - topos).at(grid).altaz()[0].degrees
        cases.append({"satellite": satellite_id, "site": site_id, "start": start, "end": end,
                      "minimumAltitude": MINIMUM_ALTITUDE, "darknessSunAltitude": DARK_SUN_ALTITUDE,
                      "windowAltitudeRange": [float(altitudes.min()), float(altitudes.max())],
                      "passes": passes})
        # Looks at fixed offsets from the window start, whether or not the satellite is above the horizon.
        for offset in (0.0, 5400.0, 40000.0, 100000.0, 200000.0):
            seconds = start + offset
            t, difference, alt, az, distance = topocentric(satellite, topos, seconds)
            lat, lon, dist, lat_rate, lon_rate, range_rate = difference.frame_latlon_and_rates(topos)
            looks.append({
                "satellite": satellite_id, "site": site_id, "time": seconds,
                "altitude": alt, "azimuth": az, "rangeKilometers": distance,
                "rangeRateKilometersPerSecond": float(range_rate.km_per_s),
                "isSunlit": sunlit(satellite, seconds),
                "sunAltitude": sun_altitude(topos, seconds),
            })
        print(satellite_id, site_id, len(passes), "passes,", sum(1 for p in passes if p["visible"]), "with a visible part")

    # Earth-shadow transitions of two satellites over one day, 5 s grid refined to a millisecond.
    shadow = []
    for satellite_id in ("iss", "starlink"):
        satellite = satellites[satellite_id]
        start = WINDOW_ORIGIN.timestamp() + 4 * 3600.0
        grid = [start + 5.0 * k for k in range(0, 17281)]
        t_grid = ts.from_datetimes(times_array(grid))
        lit = satellite.at(t_grid).is_sunlit(eph)
        transitions = []
        for k in range(1, len(grid)):
            if bool(lit[k]) != bool(lit[k - 1]):
                state = bool(lit[k])
                edge = bisect(lambda s: sunlit(satellite, s) == state, grid[k - 1], grid[k])
                transitions.append({"time": edge, "entersSunlight": state})
            if len(transitions) >= 10:
                break
        shadow.append({"satellite": satellite_id, "start": start, "transitions": transitions})

    # SGP4 states of the `sgp4` package (TEME) at times from the epoch, for every reference satellite.
    states = []
    for satellite_id, record in by_id.items():
        model = satellites[satellite_id].model
        for minutes in (0.0, 90.0, 1440.0, 4320.0, -720.0, 20000.0):
            error, position, velocity = model.sgp4_tsince(minutes)
            states.append({
                "satellite": satellite_id, "minutes": minutes, "error": int(error),
                "position": list(position) if error == 0 else None,
                "velocity": list(velocity) if error == 0 else None,
            })

    # The Sun's apparent position in TEME and Greenwich mean sidereal time at a few dates.
    from skyfield.sgp4lib import TEME

    frames = []
    for moment in (dt.datetime(2026, 1, 1, 0, 0), dt.datetime(2026, 4, 1, 6, 30), dt.datetime(2026, 7, 1, 18, 0),
                   dt.datetime(2026, 10, 18, 12, 0), dt.datetime(2026, 12, 31, 23, 59, 30),
                   dt.datetime(2027, 6, 15, 3, 15)):
        moment = moment.replace(tzinfo=dt.timezone.utc)
        t = ts.from_datetime(moment)
        apparent = earth.at(t).observe(sun).apparent()
        frames.append({
            "time": moment.timestamp(),
            "sunTemeKilometers": [float(v) for v in apparent.frame_xyz(TEME).km],
            "greenwichMeanSiderealTimeDegrees": float(t.gmst * 15.0),
        })

    document = {
        "generator": "Tools/make_satellite_fixtures.py passes",
        "skyfield": skyfield.__version__,
        "ephemeris": "DE421",
        "elements": "satellite_omm_sample.json (CelesTrak GP snapshot of 2026-10-18)",
        "sites": SITES,
        "satellites": [s for s, _, _ in SATELLITES],
        "cases": cases,
        "looks": looks,
        "shadowTransitions": shadow,
        "sgp4States": states,
        "frames": frames,
    }
    (out / "satellite_reference.json").write_text(json.dumps(document, indent=1) + "\n")
    print("wrote satellite_reference.json")


# ---------------------------------------------------------------------------------------
# streaks
# ---------------------------------------------------------------------------------------

# Frames: (site, UTC start, boresight azimuth, altitude, width, height, roll, exposure seconds)
STREAK_CASES = [
    ("boulder", dt.datetime(2026, 10, 19, 1, 30, tzinfo=dt.timezone.utc), 200.0, 50.0, 100.0, 70.0, 0.0, 120.0),
    ("boulder", dt.datetime(2026, 10, 19, 1, 30, tzinfo=dt.timezone.utc), 270.0, 30.0, 40.0, 27.0, 90.0, 60.0),
    ("sydney", dt.datetime(2026, 10, 18, 9, 30, tzinfo=dt.timezone.utc), 90.0, 20.0, 60.0, 40.0, -20.0, 90.0),
    ("boulder", dt.datetime(2026, 10, 19, 2, 0, tzinfo=dt.timezone.utc), 123.0, 90.0, 90.0, 60.0, 30.0, 120.0),
    ("tromso", dt.datetime(2026, 10, 18, 19, 0, tzinfo=dt.timezone.utc), 10.0, 40.0, 24.0, 16.0, 0.0, 120.0),
]
STREAK_RATE_WINDOW = 120.0
STREAK_SUMMARY_ALTITUDE = 20.0


STREAK_VARIANTS = 24


def synthetic_constellation(base: list[dict]) -> list[dict]:
    """A constellation of 124 x 24 = 2976 element sets: each Starlink record of the sample copied 24 times with
    the node moved by 15 degrees and the mean anomaly by 37 degrees per copy (catalog number
    200000 + 1000 * copy + position in the sample).  The tests rebuild it with the same arithmetic."""
    records = []
    for copy in range(STREAK_VARIANTS):
        for position, record in enumerate(base):
            changed = dict(record)
            changed["RA_OF_ASC_NODE"] = (record["RA_OF_ASC_NODE"] + 15.0 * copy) % 360.0
            changed["MEAN_ANOMALY"] = (record["MEAN_ANOMALY"] + 37.0 * copy) % 360.0
            changed["NORAD_CAT_ID"] = 200000 + 1000 * copy + position
            records.append(changed)
    return records


def make_streaks(out: Path, python_path: str | None, cache: Path) -> None:
    if python_path:
        sys.path.insert(0, python_path)
    import numpy as np
    from skyfield.api import EarthSatellite, Loader, wgs84

    cache.mkdir(parents=True, exist_ok=True)
    bsp = cache / "de421.bsp"
    if not bsp.exists():
        download(DE421_URL, bsp, DE421_SHA256)
    loader = Loader(str(cache))
    eph = loader("de421.bsp")
    ts = loader.timescale(builtin=True)

    satellites = []
    for record in synthetic_constellation(json.loads((out / "satellite_starlink_sample.json").read_text())):
        satellites.append((record["NORAD_CAT_ID"], EarthSatellite.from_omm(ts, dict(record))))

    def axes(azimuth, altitude, roll):
        a, e, rho = (math.radians(v) for v in (azimuth, altitude, roll))
        boresight = np.array([math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)])
        level = np.array([0.0, 0.0, 1.0]) - boresight * boresight[2]
        if np.linalg.norm(level) < 1e-6:
            level = np.array([0.0, 1.0, 0.0]) - boresight * boresight[1]
        up_level = level / np.linalg.norm(level)
        right_level = np.cross(boresight, up_level)
        up = up_level * math.cos(rho) + right_level * math.sin(rho)
        right = right_level * math.cos(rho) - up_level * math.sin(rho)
        return boresight, up, right

    cases = []
    for site_id, start_time, azimuth, altitude, width, height, roll, exposure in STREAK_CASES:
        site = SITES[site_id]
        topos = wgs84.latlon(site["latitude"], site["longitude"], site["elevation"])
        start = start_time.timestamp()
        window = max(exposure, STREAK_RATE_WINDOW)
        offsets = np.arange(0.0, window + 1e-9, 0.1)
        t = ts.utc(start_time.year, start_time.month, start_time.day, start_time.hour, start_time.minute,
                   start_time.second + offsets)
        boresight, up, right = axes(azimuth, altitude, roll)
        half_w, half_h = math.tan(math.radians(width) / 2), math.tan(math.radians(height) / 2)
        evaluated = above = sunlit_above = 0
        crossings = []
        for number, satellite in satellites:
            alt, az, _ = (satellite - topos).at(t).altaz()
            a, e = np.radians(az.degrees), np.radians(alt.degrees)
            direction = np.stack([np.cos(e) * np.sin(a), np.cos(e) * np.cos(a), np.sin(e)], axis=1)
            lit = np.asarray(satellite.at(t).is_sunlit(eph), dtype=bool)
            evaluated += 1
            if alt.degrees[0] > 0:
                above += 1
            if alt.degrees[0] >= STREAK_SUMMARY_ALTITUDE and lit[0]:
                sunlit_above += 1
            depth = direction @ boresight
            with np.errstate(divide="ignore", invalid="ignore"):
                x = (direction @ right) / depth / half_w
                y = (direction @ up) / depth / half_h
            inside = (depth > 1e-9) & (np.abs(x) <= 1) & (np.abs(y) <= 1)
            condition = inside & lit & (alt.degrees >= 0.0)
            index = 0
            while index < len(condition):
                if not condition[index]:
                    index += 1
                    continue
                first = index
                while index + 1 < len(condition) and condition[index + 1]:
                    index += 1
                crossings.append({"satellite": number, "entry": start + float(offsets[first]),
                                  "exit": start + float(offsets[index])})
                index += 1
        crossings.sort(key=lambda c: (c["entry"], c["satellite"]))
        cases.append({
            "site": site_id, "start": start, "azimuth": azimuth, "altitude": altitude, "width": width,
            "height": height, "roll": roll, "exposure": exposure, "rateWindow": STREAK_RATE_WINDOW,
            "summaryAltitude": STREAK_SUMMARY_ALTITUDE,
            "evaluated": evaluated, "aboveHorizon": above, "sunlitAboveSummaryAltitude": sunlit_above,
            "crossings": crossings,
        })
        print(site_id, start_time.isoformat(), f"{width}x{height} roll {roll}:", len(crossings), "crossings,",
              sunlit_above, "sunlit above", STREAK_SUMMARY_ALTITUDE, "of", above, "above the horizon")
    document = {"generator": "Tools/make_satellite_fixtures.py streaks", "sampleInterval": 0.1,
                "sites": SITES, "satellites": [number for number, _ in satellites], "cases": cases}
    (out / "satellite_streaks.json").write_text(json.dumps(document, separators=(",", ":")) + "\n")
    print("wrote satellite_streaks.json")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["sgp4", "snapshot", "passes", "streaks"])
    parser.add_argument("--out", type=Path, required=True, help="directory that receives the fixtures")
    parser.add_argument("--python-path", help="directory with skyfield, sgp4 and numpy (passes only)")
    parser.add_argument("--cache", type=Path, default=Path("/dev/shm/satellite-fixtures-cache"),
                        help="where de421.bsp (passes) and the CelesTrak downloads (snapshot) are kept")
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    if arguments.command == "sgp4":
        make_sgp4(arguments.out)
    elif arguments.command == "snapshot":
        make_snapshot(arguments.out, arguments.cache)
    elif arguments.command == "passes":
        make_passes(arguments.out, arguments.python_path, arguments.cache)
    else:
        make_streaks(arguments.out, arguments.python_path, arguments.cache)


if __name__ == "__main__":
    main()
