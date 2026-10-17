#!/usr/bin/env python3
"""Generate LodestarKit's astronomy reference fixtures with Skyfield and JPL DE440s.

The Swift unit tests compare LodestarKit's own astronomy (sidereal time, precession,
nutation, aberration, Sun/Moon/planet ephemerides, rise/transit/set, moon phases) with the
independent results this script computes with Skyfield and the JPL DE440s ephemeris.  Every
fixture is a JSON file in ``LodestarKit/Tests/LodestarKitTests/Fixtures``; the schema and
every definition are documented in that directory's ``README.md``.

Usage (run with ``-I`` so the interpreter ignores the environment and the working
directory while it reads the downloaded ephemeris)::

    python -I Tools/make_fixtures.py                   # regenerate all fixtures
    python -I Tools/make_fixtures.py --external-check  # compare them with JPL and USNO services

The only network access is the one-time download of ``de440s.bsp`` (verified against a
pinned SHA-256 before it is read) and, for ``--external-check``, HTTPS queries to the JPL
Horizons API and the US Naval Observatory API.  Nothing that is downloaded is ever executed.
Sampling is seeded, so repeated runs with the same library versions write identical files.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as dt
import hashlib
import json
import math
import os
import random
import re
import sys
import tempfile
import urllib.parse
import urllib.request
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

# The arrays here are small, so a BLAS thread per core only adds contention (a full run was
# 2.5 times slower).  This must be set before NumPy is imported.
for _variable in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_variable, "1")

import numpy as np  # noqa: E402
import skyfield  # noqa: E402
from skyfield import almanac  # noqa: E402
from skyfield.api import Loader, Star, load_file, wgs84  # noqa: E402
from skyfield.constants import ASEC2RAD  # noqa: E402
from skyfield.constants import C as SPEED_OF_LIGHT_M_S  # noqa: E402
from skyfield.magnitudelib import planetary_magnitude  # noqa: E402
from skyfield.nutationlib import iau2000a_radians, mean_obliquity  # noqa: E402
from skyfield.searchlib import find_discrete, find_maxima  # noqa: E402
from skyfield.timelib import Time, Timescale  # noqa: E402

# ---------------------------------------------------------------------------------------
# Pinned inputs and output locations
# ---------------------------------------------------------------------------------------

EPHEMERIS_FILE = "de440s.bsp"
EPHEMERIS_URL = "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp"
# NAIF publishes only an MD5 sum for this file (3917ee56769db332790c751e2168843d in
# aa_checksums.txt next to it).  The SHA-256 below was computed from that download and is
# identical for the JPL SSD mirror https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de440s.bsp.
EPHEMERIS_SHA256 = "c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2"
EPHEMERIS_BYTES = 32_726_016

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT_DIR = REPO_ROOT / "LodestarKit" / "Tests" / "LodestarKitTests" / "Fixtures"
DEFAULT_DATA_DIR = (
    Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "lodestar-fixtures"
)

GENERATOR = "Tools/make_fixtures.py"
SCHEMA_VERSION = 1
SEED = 20261017

# ---------------------------------------------------------------------------------------
# Conventions shared with LodestarKit (DESIGN.md section 4.1)
# ---------------------------------------------------------------------------------------

H0_STANDARD_DEG = -0.5667  # stars and planets: 34 arcminutes of refraction
H0_SUN_DEG = -0.8333  # Sun: 34' of refraction plus 16' of semi-diameter
TWILIGHT_DEG = (("civil", -6.0), ("nautical", -12.0), ("astronomical", -18.0))
MOON_H0_PARALLAX_FACTOR = 0.7275  # 1 - 0.2725, with 0.2725 the Moon/Earth radius ratio
EARTH_EQUATORIAL_RADIUS_KM = 6378.14
MOON_RADIUS_KM = 1737.4
REFRACTION_TEMPERATURE_C = 10.0
REFRACTION_PRESSURE_MBAR = 1010.0
SPEED_OF_LIGHT_KM_S = SPEED_OF_LIGHT_M_S / 1000.0

UNIX_EPOCH = dt.datetime(1970, 1, 1)
UNIX_EPOCH_JD = 2440587.5
RANGE_START = dt.datetime(1950, 1, 1)
RANGE_END = dt.datetime(2050, 1, 1)
J2000_NOON = dt.datetime(2000, 1, 1, 12, 0, 0)
TODAY = dt.datetime(2026, 10, 17, 0, 0, 0)

# Search resolutions.  find_discrete/find_maxima refine each bracket until it is shorter
# than the epsilon; the rise/set results are then verified with a dense scan.
RISE_SET_STEP_DAYS = 5.0 / 1440.0
TRANSIT_STEP_DAYS = 30.0 / 1440.0
CROSSING_EPSILON_DAYS = 0.001 / 86400.0
TRANSIT_EPSILON_DAYS = 0.01 / 86400.0
DENSE_SCAN_STEP_SECONDS = 60.0
# A window with no crossing is reported as always up / always down only if the altitude
# stays at least this far (degrees) from the threshold throughout.
MIN_POLAR_MARGIN_DEG = 0.05
# Largest disagreement (seconds) tolerated between the bracketing search and Skyfield's own
# hour-angle based almanac routines.
CROSS_CHECK_TOLERANCE_S = 2.0


@dataclasses.dataclass(frozen=True)
class Site:
    """An observing site (WGS84 geodetic latitude, east-positive longitude)."""

    key: str
    name: str
    latitude: float
    longitude: float
    elevation_m: float

    def topos(self) -> Any:
        """The WGS84 `GeographicPosition` of the site."""
        return wgs84.latlon(self.latitude, self.longitude, elevation_m=self.elevation_m)

    def fields(self) -> dict[str, Any]:
        """The site fields every case carries."""
        return {
            "site": self.key,
            "lat": self.latitude,
            "lon": self.longitude,
            "elevation_m": self.elevation_m,
        }

    def description(self) -> dict[str, Any]:
        """The entry of the file-level `sites` table: the case fields plus a name."""
        return {**self.fields(), "name": self.name}


SITES = (
    Site("boulder", "Boulder, Colorado, USA", 40.0, -105.27, 1650.0),
    Site("greenwich", "Royal Observatory, Greenwich, UK", 51.48, 0.0, 0.0),
    Site("sydney", "Sydney, Australia", -33.87, 151.21, 0.0),
    Site("tromso", "Tromso, Norway (above the Arctic Circle)", 69.65, 18.96, 0.0),
    Site("quito", "Equatorial Andes near Quito, Ecuador", 0.0, -78.5, 2800.0),
    Site("paranal", "Cerro Paranal, Chile", -24.63, -70.40, 2635.0),
)
RISE_SET_SITES = SITES[:5]
RISE_SET_DATES = (
    dt.date(2026, 1, 15),
    dt.date(2026, 3, 20),
    dt.date(2026, 6, 21),
    dt.date(2026, 10, 17),
    dt.date(2026, 12, 21),
    dt.date(2030, 8, 1),
)


@dataclasses.dataclass(frozen=True)
class CatalogStar:
    """A star with ICRS J2000.0 coordinates and proper motion (parallax and RV taken as 0)."""

    name: str
    hip: int
    ra_deg: float
    dec_deg: float
    pmra_mas_per_year: float  # mu_alpha * cos(delta), the Hipparcos convention
    pmdec_mas_per_year: float

    def skyfield_star(self) -> Star:
        """The Skyfield `Star` that carries these catalogue values."""
        return Star(
            ra_hours=self.ra_deg / 15.0,
            dec_degrees=self.dec_deg,
            ra_mas_per_year=self.pmra_mas_per_year,
            dec_mas_per_year=self.pmdec_mas_per_year,
            parallax_mas=0.0,
            radial_km_per_s=0.0,
        )

    def fields(self) -> dict[str, Any]:
        """The star fields every case carries."""
        return {
            "star": self.name,
            "hip": self.hip,
            "ra_j2000_deg": self.ra_deg,
            "dec_j2000_deg": self.dec_deg,
            "pmra_mas_per_year": self.pmra_mas_per_year,
            "pmdec_mas_per_year": self.pmdec_mas_per_year,
        }


# Source: ESA 1997, The Hipparcos and Tycho Catalogues, VizieR I/239/hip_main (CDS),
# retrieved 2026-10-17.  Positions are the catalogue's ICRS J1991.25 positions moved to
# J2000.0 with the catalogue proper motion (VizieR columns _RA.icrs/_DE.icrs); proper
# motions are pmRA (= mu_alpha cos delta) and pmDE.  Parallaxes are deliberately ignored.
STARS = (
    CatalogStar("Sirius", 32349, 101.28715539, -16.71611582, -546.01, -1223.08),
    CatalogStar("Canopus", 30438, 95.98795780, -52.69566046, 19.99, 23.67),
    CatalogStar("Arcturus", 69673, 213.91530010, 19.18241030, -1093.45, -1999.40),
    CatalogStar("Vega", 91262, 279.23473511, 38.78369180, 201.02, 287.46),
    CatalogStar("Capella", 24608, 79.17232940, 45.99799111, 75.52, -427.13),
    CatalogStar("Rigel", 24436, 78.63446812, -8.20164055, 1.87, -0.56),
    CatalogStar("Betelgeuse", 27989, 88.79293860, 7.40706274, 27.33, 10.86),
    CatalogStar("Polaris", 11767, 37.95451535, 89.26410951, 44.22, -11.74),
    CatalogStar("Acrux", 60718, 186.64956584, -63.09909166, -35.37, -14.73),
    CatalogStar("Altair", 97649, 297.69582916, 8.86832198, 536.82, 385.54),
    CatalogStar("Deneb", 102098, 310.35797809, 45.28033800, 1.56, 1.55),
    CatalogStar("sigma Octantis", 104382, 317.19519016, -88.95649900, 25.96, 5.02),
)
STAR_BY_NAME = {star.name: star for star in STARS}

BODY_KEYS = ("sun", "moon", "mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune")
PLANET_KEYS = BODY_KEYS[2:]
# DE440s has no body-centre segments for Mars and the outer planets, only system
# barycentres (offset from the planet centre by at most ~200 km, i.e. < 0.07 arcsecond).
EPHEMERIS_TARGET_NAMES = {
    "sun": "sun",
    "moon": "moon",
    "mercury": "mercury",
    "venus": "venus",
    "mars": "mars barycenter",
    "jupiter": "jupiter barycenter",
    "saturn": "saturn barycenter",
    "uranus": "uranus barycenter",
    "neptune": "neptune barycenter",
}


# ---------------------------------------------------------------------------------------
# Ephemeris and time scale
# ---------------------------------------------------------------------------------------


@dataclasses.dataclass
class Sky:
    """The loaded ephemeris and time scale, with shortcuts for the bodies the builders use."""

    ts: Timescale
    eph: Any

    @property
    def earth(self) -> Any:
        """The Earth as a Skyfield target."""
        return self.eph["earth"]

    @property
    def sun(self) -> Any:
        """The Sun as a Skyfield target."""
        return self.eph["sun"]

    @property
    def moon(self) -> Any:
        """The Moon as a Skyfield target."""
        return self.eph["moon"]

    def body(self, key: str) -> Any:
        """The DE440s target for a body key (a body centre or a system barycentre)."""
        return self.eph[EPHEMERIS_TARGET_NAMES[key]]

    def observer(self, site: Site) -> Any:
        """A vector function for a site: ``observer.at(t).observe(target)`` is topocentric."""
        return self.earth + site.topos()

    def time(self, moment: dt.datetime) -> Time:
        """The `Time` whose UT1 is the given calendar value (DUT1 = 0, TT = UT1 + Delta T)."""
        return self.ts.ut1(
            moment.year, moment.month, moment.day, moment.hour, moment.minute, moment.second
        )


def sha256_of(path: Path) -> str:
    """Hex SHA-256 digest of a file, read in 1 MiB blocks."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download_ephemeris(destination: Path) -> None:
    """Download the pinned DE440s kernel to ``destination``, checking its size and SHA-256."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    received = 0
    with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".part", delete=False) as out:
        partial = Path(out.name)
        try:
            with urllib.request.urlopen(EPHEMERIS_URL, timeout=120) as response:
                for block in iter(lambda: response.read(1 << 20), b""):
                    received += len(block)
                    if received > EPHEMERIS_BYTES:
                        raise SystemExit(f"{EPHEMERIS_URL} is larger than {EPHEMERIS_BYTES} bytes")
                    digest.update(block)
                    out.write(block)
            if received != EPHEMERIS_BYTES or digest.hexdigest() != EPHEMERIS_SHA256:
                raise SystemExit(f"{EPHEMERIS_URL}: size or SHA-256 mismatch; refusing to use it")
        except BaseException:
            partial.unlink(missing_ok=True)
            raise
    partial.replace(destination)


def load_sky(data_dir: Path) -> Sky:
    """Load DE440s (downloading and verifying it first if needed) and the builtin time scale."""
    path = data_dir / EPHEMERIS_FILE
    if not path.exists():
        print(f"downloading {EPHEMERIS_URL}", file=sys.stderr)
        download_ephemeris(path)
    if sha256_of(path) != EPHEMERIS_SHA256:
        raise SystemExit(f"{path}: SHA-256 does not match the pinned DE440s digest")
    # Loader.timescale() with its default builtin=True uses the tables bundled in Skyfield
    # (IERS Delta T values and the leap-second list) and never touches the network.
    ts = Loader(str(data_dir), verbose=False).timescale()
    return Sky(ts=ts, eph=load_file(str(path)))


# ---------------------------------------------------------------------------------------
# Sampling and formatting helpers
# ---------------------------------------------------------------------------------------


def stratified_moments(
    rng: random.Random, count: int, start: dt.datetime, end: dt.datetime
) -> list[dt.datetime]:
    """One whole-second instant drawn uniformly from each of ``count`` equal sub-intervals."""
    span = int((end - start).total_seconds())
    offsets = (min(int(span * (i + rng.random()) / count), span - 1) for i in range(count))
    return [start + dt.timedelta(seconds=offset) for offset in offsets]


def sample_moments(fixed: Sequence[dt.datetime], count: int, seed_offset: int) -> list[dt.datetime]:
    """The fixed instants plus ``count`` stratified ones over 1950-2049, ascending."""
    rng = random.Random(SEED + seed_offset)
    return sorted(set(fixed) | set(stratified_moments(rng, count, RANGE_START, RANGE_END)))


def iso_seconds(moment: dt.datetime) -> str:
    """ISO-8601 text of a naive datetime that stands for a UTC (UT1-labelled) instant."""
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso_seconds(text: str) -> dt.datetime:
    """Inverse of `iso_seconds`."""
    return dt.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")


def posix_seconds(moment: dt.datetime) -> float:
    """POSIX seconds of a naive datetime that stands for a UTC (UT1-labelled) instant."""
    return (moment - UNIX_EPOCH).total_seconds()


def print_range(label: str, seconds: Sequence[float]) -> None:
    """One summary line: the smallest and largest of a list of differences in seconds."""
    print(
        f"  {label:24s} n={len(seconds):3d}  min {min(seconds):+8.1f}  max {max(seconds):+8.1f} s"
    )


def rounded(value: float, places: int) -> float:
    """Round to ``places`` decimals, as a plain float that is never negative zero."""
    return round(float(value), places) + 0.0


def instant_fields(t: Time, moment: dt.datetime) -> dict[str, Any]:
    """The fields that identify an instant in a case: `utc`, `ut1_jd` and `tt_jd`."""
    return {"utc": iso_seconds(moment), "ut1_jd": float(t.ut1), "tt_jd": float(t.tt)}


def event_fields(t: Time) -> dict[str, Any]:
    """An event instant with millisecond resolution: ISO-8601 text plus POSIX seconds."""
    unix_ms = round((float(t.ut1) - UNIX_EPOCH_JD) * 86_400_000.0)
    moment = UNIX_EPOCH + dt.timedelta(milliseconds=unix_ms)
    text = moment.strftime("%Y-%m-%dT%H:%M:%S") + f".{moment.microsecond // 1000:03d}Z"
    return {"utc": text, "unix": unix_ms / 1000.0}


def time_from_unix(sky: Sky, unix_seconds: float) -> Time:
    """The `Time` for POSIX seconds of a UT1-labelled calendar value."""
    return sky.ts.ut1_jd(UNIX_EPOCH_JD + unix_seconds / 86400.0)


def compact_json(value: Any) -> str:
    """JSON on one line without spaces; NaN and infinity are errors."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True, allow_nan=False)


def render_json(value: Any, expand: int, level: int = 0) -> str:
    """Pretty-print the outer ``expand`` levels of a value; deeper values stay on one line."""
    if expand <= 0 or not isinstance(value, (dict, list)) or not value:
        return compact_json(value)
    pad = "  " * (level + 1)
    if isinstance(value, dict):
        lines = [
            f"{pad}{json.dumps(key)}: {render_json(item, expand - 1, level + 1)}"
            for key, item in value.items()
        ]
        return "{\n" + ",\n".join(lines) + "\n" + "  " * level + "}"
    lines = [f"{pad}{render_json(item, expand - 1, level + 1)}" for item in value]
    return "[\n" + ",\n".join(lines) + "\n" + "  " * level + "]"


def render_document(doc: dict[str, Any], expand_by_key: dict[str, int]) -> str:
    """One top-level key per line; arrays one element per line; ``expand_by_key`` goes deeper."""
    lines = [
        f"  {json.dumps(key)}: {render_json(value, expand_by_key.get(key, 1), 1)}"
        for key, value in doc.items()
    ]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def time_scale_note(sky: Sky) -> str:
    """The note, shared by all files, that states the time-scale convention."""
    table_tt, _ = sky.ts.delta_t_table
    first = sky.ts.tt_jd(float(table_tt[0])).tt_strftime("%Y-%m-%d")
    last = sky.ts.tt_jd(float(table_tt[-1])).tt_strftime("%Y-%m-%d")
    return (
        "Time: every instant is its calendar value read as UT1 (DUT1 = 0, the same assumption "
        "as LodestarKit's JulianDate(date:)); TT = UT1 + DeltaT with DeltaT from Skyfield's "
        f"builtin tables (IERS daily values {first}..{last}, Stephenson/Morrison/Hohenkerk "
        "splines and parabola elsewhere). No IERS download, no polar motion."
    )


def document(sky: Sky, description: str, notes: Sequence[str], **sections: Any) -> dict[str, Any]:
    """A fixture document: the common header followed by the file's own sections."""
    return {
        "schema_version": SCHEMA_VERSION,
        "generator": GENERATOR,
        "skyfield_version": skyfield.__version__,
        "ephemeris": f"JPL DE440s ({EPHEMERIS_FILE}, SHA-256 {EPHEMERIS_SHA256})",
        "description": description,
        "notes": [time_scale_note(sky), *notes],
        **sections,
    }


# ---------------------------------------------------------------------------------------
# 1. sidereal.json
# ---------------------------------------------------------------------------------------

SIDEREAL_FIXED = (
    dt.datetime(1987, 4, 10, 0, 0, 0),
    dt.datetime(1987, 4, 10, 19, 21, 0),
    J2000_NOON,
    TODAY,
)


def build_sidereal(sky: Sky) -> dict[str, Any]:
    """Build sidereal.json: time scales, sidereal time, precession and nutation."""
    cases = []
    for moment in sample_moments(SIDEREAL_FIXED, 40, seed_offset=1):
        t = sky.time(moment)
        d_psi, d_eps = iau2000a_radians(t)
        beta = sky.earth.at(t).velocity.km_per_s / SPEED_OF_LIGHT_KM_S
        cases.append(
            {
                **instant_fields(t, moment),
                "delta_t_seconds": rounded(t.delta_t, 6),
                "gmst_hours": rounded(t.gmst, 10),
                "gast_hours": rounded(t.gast, 10),
                "nutation_dpsi_arcsec": rounded(d_psi / ASEC2RAD, 6),
                "nutation_deps_arcsec": rounded(d_eps / ASEC2RAD, 6),
                "mean_obliquity_deg": rounded(mean_obliquity(t.tdb) / 3600.0, 9),
                "precession_matrix": [rounded(x, 15) for x in t.precession_matrix().flatten()],
                "nutation_matrix": [rounded(x, 15) for x in t.nutation_matrix().flatten()],
                "earth_beta_icrs": [rounded(component, 12) for component in beta],
            }
        )
    return document(
        sky,
        "Time-scale and sidereal-time reference values.",
        [
            "gmst_hours: Greenwich mean sidereal time in hours [0, 24), IAU 2006 "
            "(Skyfield Time.gmst).",
            "gast_hours: Greenwich apparent sidereal time in hours [0, 24) = gmst + equation of "
            "the equinoxes (IAU 2000A nutation plus complementary terms; Skyfield Time.gast).",
            "delta_t_seconds = TT - UT1; tt_jd - ut1_jd equals delta_t_seconds / 86400.",
            "nutation_dpsi_arcsec, nutation_deps_arcsec: IAU 2000A nutation in longitude and "
            "obliquity. mean_obliquity_deg: IAU 2006 mean obliquity of the ecliptic of date.",
            "precession_matrix: 3x3, row-major, IAU 2006 precession from the mean equator and "
            "equinox of J2000.0 to the mean equator and equinox of date (v_date = P v_J2000; "
            "ICRS frame bias not included). nutation_matrix: 3x3, row-major, IAU 2000A "
            "nutation from the mean to the true equator and equinox of date "
            "(v_true = N v_mean). The true-of-date vector of a J2000 mean vector is N P v.",
            "earth_beta_icrs: barycentric velocity of the Earth divided by c, ICRS axes (the "
            "Sun's own barycentric velocity, up to 16 m/s, is therefore included).",
            "1987-04-10T00:00:00Z and 1987-04-10T19:21:00Z are Meeus, Astronomical Algorithms "
            "(2nd ed.), examples 12.a and 12.b.",
        ],
        cases=cases,
    )


# ---------------------------------------------------------------------------------------
# 2. stars_apparent.json
# ---------------------------------------------------------------------------------------


def build_stars(sky: Sky) -> dict[str, Any]:
    """Build stars_apparent.json: 12 stars x 10 instants x 2 sites."""
    observers = {site.key: sky.observer(site) for site in SITES}
    cases = []
    for i, moment in enumerate(sample_moments((J2000_NOON, TODAY), 8, seed_offset=2)):
        t = sky.time(moment)
        sites = (SITES[i % len(SITES)], SITES[(i + 3) % len(SITES)])
        for star in STARS:
            target = star.skyfield_star()
            geocentric = sky.earth.at(t).observe(target).apparent()
            ra, dec, _ = geocentric.radec(epoch="date")
            for site in sites:
                apparent = observers[site.key].at(t).observe(target).apparent()
                alt, az, _ = apparent.altaz()
                alt_refracted, _, _ = apparent.altaz(
                    temperature_C=REFRACTION_TEMPERATURE_C, pressure_mbar=REFRACTION_PRESSURE_MBAR
                )
                cases.append(
                    {
                        **instant_fields(t, moment),
                        **site.fields(),
                        **star.fields(),
                        "ra_apparent_deg": rounded(ra.degrees, 9),
                        "dec_apparent_deg": rounded(dec.degrees, 9),
                        "az_deg": rounded(az.degrees, 9),
                        "alt_deg": rounded(alt.degrees, 9),
                        "alt_refracted_deg": (
                            rounded(alt_refracted.degrees, 9) if alt.degrees >= -1.0 else None
                        ),
                    }
                )
    return document(
        sky,
        "Apparent places and horizontal coordinates of 12 bright stars.",
        [
            "Stars: Skyfield Star(ra_hours=ra_j2000_deg/15, dec_degrees=dec_j2000_deg, "
            "ra_mas_per_year=pmra_mas_per_year, dec_mas_per_year=pmdec_mas_per_year, "
            "parallax_mas=0, radial_km_per_s=0); pmra_mas_per_year is mu_alpha*cos(delta). "
            "Positions and proper motions are from the Hipparcos catalogue (ESA 1997), the "
            "ICRS J1991.25 positions moved to J2000.0 with the proper motion.",
            "ra_apparent_deg, dec_apparent_deg: geocentric apparent place in the true equator "
            "and equinox of date (proper motion, annual aberration, light deflection, "
            "IAU 2006 precession, IAU 2000A nutation).",
            "az_deg (from North toward East) and alt_deg: topocentric, geometric (no "
            "atmospheric refraction), measured from the WGS84 geodetic vertical. They include "
            "annual and diurnal aberration (diurnal aberration is up to 0.32 arcsec).",
            "alt_refracted_deg: Skyfield altaz(temperature_C=10, pressure_mbar=1010). Skyfield "
            "iterates alt_obs = alt + r(alt_obs), r(h) = 0.016667 deg / tan((h + 7.31/(h + "
            "4.4)) deg) * 0.28 * P / (T + 273) (Bennett's formula evaluated at the observed "
            "altitude h; P in mbar, T in Celsius), until the change is below 3e-5 deg, and "
            "applies no refraction for an observed altitude below -1 deg or above 89.9 deg. "
            "The value is null where alt_deg < -1.",
        ],
        sites=[site.description() for site in SITES],
        stars=[star.fields() for star in STARS],
        cases=cases,
    )


# ---------------------------------------------------------------------------------------
# 3. bodies_apparent.json
# ---------------------------------------------------------------------------------------


def heliocentric_distance_au(sky: Sky, key: str, t: Time, light_time_days: float) -> float:
    """Sun-planet distance with both bodies at the instant the light left the planet."""
    emitted = sky.ts.tt_jd(float(t.tt) - float(light_time_days))
    return float((sky.body(key) - sky.sun).at(emitted).distance().au)


def build_bodies(sky: Sky) -> dict[str, Any]:
    """Build bodies_apparent.json: 9 bodies x 50 instants, each instant at one site."""
    observers = {site.key: sky.observer(site) for site in SITES}
    cases = []
    for i, moment in enumerate(sample_moments((J2000_NOON, TODAY), 48, seed_offset=3)):
        t = sky.time(moment)
        site = SITES[i % len(SITES)]
        geocentre = sky.earth.at(t)
        observer = observers[site.key].at(t)
        sun_apparent = geocentre.observe(sky.sun).apparent()
        for key in BODY_KEYS:
            target = sky.body(key)
            astrometric = geocentre.observe(target)
            geocentric = astrometric.apparent()
            ra, dec, distance = geocentric.radec(epoch="date")
            ra_icrs, dec_icrs, _ = geocentric.radec()
            topocentric = observer.observe(target).apparent()
            ra_topo, dec_topo, _ = topocentric.radec(epoch="date")
            alt, az, _ = topocentric.altaz()
            case = {
                **instant_fields(t, moment),
                **site.fields(),
                "body": key,
                "ra_apparent_j2000_deg": rounded(ra_icrs.degrees, 9),
                "dec_apparent_j2000_deg": rounded(dec_icrs.degrees, 9),
                "ra_apparent_deg": rounded(ra.degrees, 9),
                "dec_apparent_deg": rounded(dec.degrees, 9),
                "ra_topo_deg": rounded(ra_topo.degrees, 9),
                "dec_topo_deg": rounded(dec_topo.degrees, 9),
                "distance_au": rounded(distance.au, 12),
                "az_deg": rounded(az.degrees, 9),
                "alt_deg": rounded(alt.degrees, 9),
                "illuminated_fraction": None,
                "phase_angle_deg": None,
                "elongation_deg": None,
                "heliocentric_distance_au": None,
                "apparent_magnitude": None,
            }
            if key != "sun":
                case["illuminated_fraction"] = rounded(astrometric.fraction_illuminated(sky.sun), 9)
                case["phase_angle_deg"] = rounded(astrometric.phase_angle(sky.sun).degrees, 9)
                case["elongation_deg"] = rounded(
                    geocentric.separation_from(sun_apparent).degrees, 9
                )
            if key in PLANET_KEYS:
                case["heliocentric_distance_au"] = rounded(
                    heliocentric_distance_au(sky, key, t, astrometric.light_time), 12
                )
                magnitude = float(planetary_magnitude(astrometric))
                case["apparent_magnitude"] = (
                    rounded(magnitude, 3) if math.isfinite(magnitude) else None
                )
            cases.append(case)
    return document(
        sky,
        "Apparent geocentric and topocentric places of the Sun, Moon and planets.",
        [
            "Bodies are DE440s targets: sun, moon, mercury and venus (body centres) and the "
            "system barycentres of Mars, Jupiter, Saturn, Uranus and Neptune (DE440s has no "
            "body-centre segments for these; the offset is below 0.07 arcsec).",
            "ra_apparent_j2000_deg, dec_apparent_j2000_deg: geocentric apparent direction "
            "(light time, light deflection, annual aberration) on the ICRS axes, which are the "
            "mean equator and equinox of J2000.0 to within 20 mas; this is the direction of "
            "LodestarKit's BodyState.geocentricJ2000, before precession and nutation.",
            "ra_apparent_deg, dec_apparent_deg: the same direction in the true equator and "
            "equinox of date (IAU 2006 precession, IAU 2000A nutation). distance_au: "
            "geocentric, light-time corrected.",
            "ra_topo_deg, dec_topo_deg: topocentric apparent place in the same frame, seen from "
            "the site of the same case (WGS84; includes parallax and diurnal aberration).",
            "az_deg (from North toward East) and alt_deg: topocentric, geometric (no "
            "atmospheric refraction) altitude of the body's centre.",
            "illuminated_fraction = (1 + cos(phase_angle_deg)) / 2, phase_angle_deg the "
            "geocentric Sun-body-Earth angle (Skyfield astrometric.phase_angle(sun); the Sun's "
            "position is taken at the observation instant). elongation_deg: angle between the "
            "geocentric apparent directions of the body and the Sun. All three are null for "
            "the Sun.",
            "heliocentric_distance_au (planets only): Sun-planet distance with both bodies at "
            "the instant the light left the planet (observation time minus light time).",
            "apparent_magnitude (planets only): Mallama and Hilton (2018) via Skyfield "
            "magnitudelib; null if the model is undefined (NaN), which does not happen for "
            "these instants.",
        ],
        sites=[site.description() for site in SITES],
        cases=cases,
    )


# ---------------------------------------------------------------------------------------
# 4. riseset.json
# ---------------------------------------------------------------------------------------


def moon_h0_as_specified(sky: Sky) -> Callable[[Time], np.ndarray]:
    """h0 = 0.7275 pi - 0.5667 deg, pi = asin(6378.14 km / geocentric distance)."""

    def h0(t: Time) -> np.ndarray:
        distance_km = sky.earth.at(t).observe(sky.moon).distance().km
        parallax = np.degrees(np.arcsin(EARTH_EQUATORIAL_RADIUS_KM / distance_km))
        return MOON_H0_PARALLAX_FACTOR * parallax + H0_STANDARD_DEG

    return h0


def moon_h0_upper_limb(sky: Sky, observer: Any) -> Callable[[Time], np.ndarray]:
    """h0 = -0.5667 deg - semi-diameter, the centre altitude with the upper limb at -34'."""

    def h0(t: Time) -> np.ndarray:
        distance_km = observer.at(t).observe(sky.moon).distance().km
        return H0_STANDARD_DEG - np.degrees(np.arcsin(MOON_RADIUS_KM / distance_km))

    return h0


def altitude_function(observer: Any, target: Any) -> Callable[[Time], np.ndarray]:
    """Topocentric apparent geometric altitude (degrees) of ``target`` as a function of time."""

    def altitude(t: Time) -> np.ndarray:
        return observer.at(t).observe(target).apparent().altaz()[0].degrees

    return altitude


def crossing_record(
    sky: Sky,
    window: tuple[Time, Time],
    altitude: Callable[[Time], np.ndarray],
    h0: float | Callable[[Time], np.ndarray],
    label: str,
) -> dict[str, Any]:
    """All crossings of ``altitude`` through ``h0`` inside the window, verified by a dense scan.

    The search is ``find_discrete`` on the predicate "altitude > h0".  The result is then
    checked against a 60-second scan: the crossings must be exactly the sign changes the scan
    sees, each inside the scan interval that contains its sign change.  A window without
    crossings is reported as always up / always down only if the altitude stays at least
    ``MIN_POLAR_MARGIN_DEG`` away from the threshold.
    """
    t0, t1 = window

    def threshold(t: Time) -> Any:
        return h0(t) if callable(h0) else h0

    def is_up(t: Time) -> np.ndarray:
        return altitude(t) > threshold(t)

    is_up.step_days = RISE_SET_STEP_DAYS  # type: ignore[attr-defined]
    times, states = find_discrete(t0, t1, is_up, epsilon=CROSSING_EPSILON_DAYS)

    scan_count = round((float(t1.tt) - float(t0.tt)) * 86400.0 / DENSE_SCAN_STEP_SECONDS) + 1
    scan = sky.ts.tt_jd(np.linspace(float(t0.tt), float(t1.tt), scan_count))
    margin = altitude(scan) - threshold(scan)
    changes = np.flatnonzero(np.diff(margin > 0))
    scan_tt, found_tt = np.asarray(scan.tt), np.asarray(times.tt)
    if len(changes) != len(found_tt) or not all(
        scan_tt[k] <= tt <= scan_tt[k + 1] for k, tt in zip(changes, found_tt, strict=True)
    ):
        raise SystemExit(f"{label}: crossing search disagrees with the dense scan")

    crossings = []
    for index in range(len(found_tt)):
        crossing = {"kind": "rise" if states[index] else "set", **event_fields(times[index])}
        if callable(h0):
            crossing["h0_deg"] = rounded(float(threshold(times[index])), 6)
        crossings.append(crossing)

    always_up = always_down = False
    if not crossings:
        if float(np.min(np.abs(margin))) < MIN_POLAR_MARGIN_DEG:
            raise SystemExit(f"{label}: altitude grazes the horizon; choose another date")
        always_up = bool(margin[0] > 0)
        always_down = not always_up
    return {
        "h0_deg": None if callable(h0) else h0,
        "crossings": crossings,
        "always_up": always_up,
        "always_down": always_down,
    }


def transit_records(
    window: tuple[Time, Time], altitude: Callable[[Time], np.ndarray]
) -> list[dict[str, Any]]:
    """Upper culminations (local maxima of the altitude) inside the window."""

    def curve(t: Time) -> np.ndarray:
        return altitude(t)

    curve.step_days = TRANSIT_STEP_DAYS  # type: ignore[attr-defined]
    times, altitudes = find_maxima(*window, curve, epsilon=TRANSIT_EPSILON_DAYS)
    return [
        {**event_fields(times[i]), "altitude_deg": rounded(altitudes[i], 9)}
        for i in range(len(times))
    ]


def window_for(site: Site, day: dt.date) -> tuple[dt.datetime, dt.datetime]:
    """Local noon to the next local noon, with local noon = 12:00 UT - longitude/15 hours."""
    noon = dt.datetime(day.year, day.month, day.day, 12, 0, 0)
    start = noon - dt.timedelta(seconds=round(site.longitude * 240.0))
    return start, start + dt.timedelta(days=1)


def riseset_targets(sky: Sky) -> dict[str, Any]:
    """The six objects whose rise, set and transit are tabulated, by fixture key."""
    return {
        "sun": sky.sun,
        "moon": sky.moon,
        "jupiter": sky.body("jupiter"),
        "venus": sky.body("venus"),
        "sirius": STAR_BY_NAME["Sirius"].skyfield_star(),
        "vega": STAR_BY_NAME["Vega"].skyfield_star(),
    }


def build_riseset(sky: Sky) -> dict[str, Any]:
    """Build riseset.json: 5 sites x 6 dates x 6 objects."""
    targets = riseset_targets(sky)
    cases = []
    for site in RISE_SET_SITES:
        observer = sky.observer(site)
        for day in RISE_SET_DATES:
            start, end = window_for(site, day)
            window = (sky.time(start), sky.time(end))
            objects: dict[str, Any] = {}
            for key, target in targets.items():
                label = f"{site.key} {day} {key}"
                altitude = altitude_function(observer, target)
                record: dict[str, Any] = {}
                if key == "sun":
                    record["horizon"] = crossing_record(sky, window, altitude, H0_SUN_DEG, label)
                    for name, degrees in TWILIGHT_DEG:
                        record[name] = crossing_record(
                            sky, window, altitude, degrees, f"{label} {name}"
                        )
                elif key == "moon":
                    record["horizon"] = crossing_record(
                        sky, window, altitude, moon_h0_as_specified(sky), label
                    )
                    record["horizon_upper_limb"] = crossing_record(
                        sky, window, altitude, moon_h0_upper_limb(sky, observer), label + " limb"
                    )
                else:
                    record["horizon"] = crossing_record(
                        sky, window, altitude, H0_STANDARD_DEG, label
                    )
                record["transits"] = transit_records(window, altitude)
                objects[key] = record
            cases.append(
                {
                    **site.fields(),
                    "date": day.isoformat(),
                    "window_start_utc": iso_seconds(start),
                    "window_end_utc": iso_seconds(end),
                    "objects": objects,
                }
            )
    return document(
        sky,
        "Rise, set, transit and twilight times for 5 sites x 6 dates x 6 objects.",
        [
            "Window: local noon of 'date' to the next local noon, where local noon is "
            "12:00:00 UT minus longitude/15 hours (rounded to whole seconds). Events are "
            "searched strictly inside the window.",
            "Altitude: topocentric, geometric (no refraction) altitude of the body's centre "
            "(Skyfield apparent place, WGS84 vertical). A crossing is an instant where "
            "altitude - h0 changes sign: kind 'rise' = upward, 'set' = downward; the same "
            "kinds are used for dawn (rise) and dusk (set) at the twilight thresholds.",
            "h0 (degrees): stars and planets -0.5667; Sun -0.8333; Sun twilights -6 (civil), "
            "-12 (nautical), -18 (astronomical). Crossings are resolved to 1 ms.",
            "WARNING (Moon): DESIGN.md section 4.1 prescribes h0 = 0.7275*pi - 0.5667 deg for "
            "the Moon. That is Meeus' threshold for the GEOCENTRIC altitude of the Moon's "
            "centre; applied to the topocentric altitude, as for every other body here, it "
            "puts rise and set about pi (~0.95 deg) too high: about 4 minutes off at the "
            "equator, 5-10 minutes at 34-52 degrees latitude, up to 16 minutes at 70 degrees, "
            "as JPL Horizons and the US Naval Observatory confirm (see README.md).",
            "moon.horizon implements the DESIGN.md text literally: topocentric centre "
            "altitude vs h0 = 0.7275*pi - 0.5667 deg, pi = asin(6378.14 km / geocentric "
            "distance) at the crossing instant (h0 is recorded per crossing).",
            "moon.horizon_upper_limb is the real event: topocentric centre altitude vs "
            "h0 = -0.5667 deg - asin(1737.4 km / topocentric distance), i.e. the upper limb on "
            "the horizon after 34 arcminutes of refraction (USNO and JPL Horizons definition). "
            "Meeus' geocentric formulation (geocentric altitude vs 0.7275*pi - 0.5667 deg) "
            "gives the same instants to within 3 seconds.",
            "A list with no crossings carries always_up or always_down (the altitude stays "
            "at least 0.05 deg from h0 for the whole window).",
            "transits: upper culminations, i.e. local maxima of the topocentric geometric "
            "altitude, with that altitude in degrees; culminations below the horizon are "
            "listed too. For the Sun, Moon and planets the time can differ from the meridian "
            "passage by seconds (Sun, planets) to many minutes (Moon at high latitude). A "
            "window can hold zero (Moon) or, rarely, two transits.",
        ],
        sites=[site.description() for site in RISE_SET_SITES],
        cases=cases,
    )


# ---------------------------------------------------------------------------------------
# 5. moon_phases.json
# ---------------------------------------------------------------------------------------

PHASE_NAMES = ("new", "first_quarter", "full", "last_quarter")
PHASES_START = dt.datetime(2024, 1, 1)
PHASES_END = dt.datetime(2029, 1, 1)
# One lunation of padding, so that the age of the Moon is known for samples near the start.
PHASES_PADDED_START = dt.datetime(2023, 11, 1)


def build_moon_phases(sky: Sky) -> dict[str, Any]:
    """Build moon_phases.json: principal phases 2024-2028 plus illumination samples."""
    times, indices = find_discrete(
        sky.time(PHASES_PADDED_START),
        sky.time(PHASES_END),
        almanac.moon_phases(sky.eph),
        epsilon=CROSSING_EPSILON_DAYS,
    )
    all_phases = [(times[i], PHASE_NAMES[int(indices[i])]) for i in range(len(times))]
    new_moons = [float(t.tt) for t, name in all_phases if name == "new"]
    lower, upper = float(sky.time(PHASES_START).tt), float(sky.time(PHASES_END).tt)
    phases = [
        {"phase": name, **event_fields(t)} for t, name in all_phases if lower <= float(t.tt) < upper
    ]

    rng = random.Random(SEED + 5)
    samples = []
    for moment in sorted(set(stratified_moments(rng, 30, PHASES_START, PHASES_END))):
        t = sky.time(moment)
        astrometric = sky.earth.at(t).observe(sky.moon)
        previous_new = max(tt for tt in new_moons if tt <= float(t.tt))
        samples.append(
            {
                **instant_fields(t, moment),
                "illuminated_fraction": rounded(astrometric.fraction_illuminated(sky.sun), 9),
                "phase_angle_deg": rounded(astrometric.phase_angle(sky.sun).degrees, 9),
                "ecliptic_elongation_deg": rounded(almanac.moon_phase(sky.eph, t).degrees, 9),
                "age_days": rounded(float(t.tt) - previous_new, 6),
            }
        )
    return document(
        sky,
        "Principal moon phases 2024-2028 and illumination samples.",
        [
            "phases: every new moon, first quarter, full moon and last quarter with "
            f"{PHASES_START:%Y-%m-%d} <= instant < {PHASES_END:%Y-%m-%d}, from "
            "skyfield.almanac.moon_phases: the instants where the geocentric apparent ecliptic "
            "longitude of the Moon minus that of the Sun (true ecliptic of date) is 0, 90, 180, "
            "270 degrees, resolved to 1 ms. 'utc' is the instant read as UT1; 'unix' is POSIX "
            "seconds of that same calendar value.",
            "samples.illuminated_fraction, samples.phase_angle_deg: geocentric; phase_angle_deg "
            "is the Sun-Moon-Earth angle at the Moon (0 = full, 180 = new) and "
            "illuminated_fraction = (1 + cos(phase_angle_deg)) / 2.",
            "samples.ecliptic_elongation_deg: Skyfield almanac.moon_phase, the apparent ecliptic "
            "longitude of the Moon minus that of the Sun in [0, 360): 0 new, 90 first quarter, "
            "180 full, 270 last quarter; the Moon is waxing while it is below 180.",
            "samples.age_days: days since the preceding new moon of the 'phases' list "
            "(the file also searches one lunation before the first listed phase).",
        ],
        phases=phases,
        samples=samples,
    )


# ---------------------------------------------------------------------------------------
# Independent cross-checks run on every generation
# ---------------------------------------------------------------------------------------


def check_ranges(name: str, cases: Sequence[dict[str, Any]]) -> None:
    """Guard the numeric invariants the Swift tests rely on."""
    limits = {
        "ra_apparent_j2000_deg": (0.0, 360.0),
        "ra_apparent_deg": (0.0, 360.0),
        "ra_topo_deg": (0.0, 360.0),
        "az_deg": (0.0, 360.0),
        "dec_apparent_j2000_deg": (-90.0, 90.0),
        "dec_apparent_deg": (-90.0, 90.0),
        "dec_topo_deg": (-90.0, 90.0),
        "alt_deg": (-90.0, 90.0),
        "illuminated_fraction": (0.0, 1.0),
        "phase_angle_deg": (0.0, 180.0),
        "elongation_deg": (0.0, 180.0),
    }
    for case in cases:
        for field, (low, high) in limits.items():
            value = case.get(field)
            if value is not None and not low <= value <= high:
                raise SystemExit(f"{name}: {field}={value} outside [{low}, {high}] in {case}")


def cross_check_riseset(sky: Sky, riseset: dict[str, Any]) -> tuple[float, float]:
    """Compare the results with Skyfield's own hour-angle based almanac searches.

    ``almanac.find_risings/find_settings/find_transits`` (Skyfield >= 1.47) solve the problem
    with a different algorithm than the bracketing search used here, so agreement validates
    the horizon rules and the window bookkeeping.  Returns the largest rise/set discrepancy
    and the largest fixed-star transit discrepancy, both in seconds.
    """
    targets = riseset_targets(sky)
    rules: dict[str, list[tuple[str, float | None]]] = {
        "sun": [("horizon", H0_SUN_DEG), *TWILIGHT_DEG],
        "moon": [("horizon_upper_limb", None)],
    }
    finders = (("rise", almanac.find_risings), ("set", almanac.find_settings))
    worst = {"crossing": 0.0, "transit": 0.0}

    def compare(kind: str, label: str, events: list[dict[str, Any]], reference: list[Time]) -> None:
        if len(events) != len(reference):
            raise SystemExit(
                f"cross-check {label}: {len(events)} events vs {len(reference)} in Skyfield"
            )
        for event, expected in zip(events, reference, strict=True):
            gap = abs(float(time_from_unix(sky, event["unix"]).tt) - float(expected.tt))
            worst[kind] = max(worst[kind], gap * 86400.0)

    for case in riseset["cases"]:
        site = next(s for s in RISE_SET_SITES if s.key == case["site"])
        observer = sky.observer(site)
        t0 = sky.time(parse_iso_seconds(case["window_start_utc"]))
        t1 = sky.time(parse_iso_seconds(case["window_end_utc"]))
        for key, record in case["objects"].items():
            label = f"{case['site']} {case['date']} {key}"
            for name, h0 in rules.get(key, [("horizon", H0_STANDARD_DEG)]):
                for kind, finder in finders:
                    found, real = finder(observer, targets[key], t0, t1, horizon_degrees=h0)
                    reference = [
                        found[i]
                        for i in range(len(found))
                        if real[i] and t0.tt < found[i].tt < t1.tt
                    ]
                    events = [c for c in record[name]["crossings"] if c["kind"] == kind]
                    compare("crossing", f"{label} {name} {kind}", events, reference)
            if key in ("sirius", "vega"):  # fixed stars: culmination == meridian transit
                meridian = almanac.find_transits(observer, targets[key], t0, t1)
                reference = [
                    meridian[i] for i in range(len(meridian)) if t0.tt < meridian[i].tt < t1.tt
                ]
                compare("transit", f"{label} transit", record["transits"], reference)
    if max(worst.values()) > CROSS_CHECK_TOLERANCE_S:
        raise SystemExit(f"rise/set differ from Skyfield's almanac by more than {worst}")
    return worst["crossing"], worst["transit"]


# ---------------------------------------------------------------------------------------
# JPL Horizons spot check
# ---------------------------------------------------------------------------------------

HORIZONS_API = "https://ssd.jpl.nasa.gov/api/horizons.api"
# Horizons commands: body centres, plus the system barycentres DE440s provides for Mars-Neptune.
HORIZONS_CENTER = {
    "sun": "10",
    "moon": "301",
    "mercury": "199",
    "venus": "299",
    "mars": "499",
    "jupiter": "599",
    "saturn": "699",
    "uranus": "799",
    "neptune": "899",
}
HORIZONS_BARYCENTER = {"mars": "4", "jupiter": "5", "saturn": "6", "uranus": "7", "neptune": "8"}


def horizons_query(**parameters: str) -> str:
    """Run one Horizons API request (HTTPS, fixed host) and return the result text."""
    query = {"OBJ_DATA": "NO", "MAKE_EPHEM": "YES", "EPHEM_TYPE": "OBSERVER", **parameters}
    encoded = urllib.parse.urlencode({key: f"'{value}'" for key, value in query.items()})
    with urllib.request.urlopen(f"{HORIZONS_API}?format=json&{encoded}", timeout=120) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if "result" not in payload:
        raise SystemExit(f"Horizons error: {payload.get('message', payload)}")
    return str(payload["result"])


def horizons_table(text: str) -> list[str]:
    """The rows between Horizons' $$SOE and $$EOE markers."""
    start, end = text.find("$$SOE"), text.find("$$EOE")
    if start < 0 or end < start:
        raise SystemExit("Horizons returned no ephemeris rows:\n" + text[:2000])
    return [line for line in text[start:end].splitlines()[1:] if line.strip()]


def horizons_rows(text: str) -> list[dict[str, str]]:
    """Rows of a CSV observer table, keyed by the column names of its header line."""
    header = next(
        line
        for line in reversed(text[: text.find("$$SOE")].splitlines())
        if line.startswith("Date_")
    )
    names = [name.strip() for name in header.split(",")]
    return [
        dict(zip(names, (v.strip() for v in line.split(",")), strict=True))
        for line in horizons_table(text)
    ]


def horizons_number(row: dict[str, str], name: str) -> float | None:
    """A numeric column of a CSV row; None where Horizons prints n.a."""
    try:
        return float(row[name])
    except ValueError:
        return None


def horizons_geocentric(
    command: str, jd_values: Sequence[float], quantities: str, time_type: str = "TT", **center: str
) -> list[dict[str, str]]:
    """CSV observer table (RA/Dec in degrees, Julian dates) for each instant of ``jd_values``."""
    text = horizons_query(
        COMMAND=command,
        TLIST=" ".join(f"{jd:.9f}" for jd in jd_values),
        TLIST_TYPE="JD",
        TIME_TYPE=time_type,
        QUANTITIES=quantities,
        ANG_FORMAT="DEG",
        EXTRA_PREC="YES",
        CSV_FORMAT="YES",
        CAL_FORMAT="JD",
        **{"CENTER": "500@399", **center},
    )
    rows = horizons_rows(text)
    if len(rows) != len(jd_values):
        raise SystemExit(f"Horizons returned {len(rows)} rows for {len(jd_values)} instants")
    return rows


def sky_offsets_arcsec(
    ra: float, dec: float, reference: tuple[float, float]
) -> tuple[float, float]:
    """Offsets (east, north) in arcseconds of (ra, dec) from a reference position, in degrees."""
    d_ra = ((ra - reference[0] + 180.0) % 360.0 - 180.0) * math.cos(math.radians(reference[1]))
    return d_ra * 3600.0, (dec - reference[1]) * 3600.0


def horizons_position(row: dict[str, str]) -> tuple[float, float]:
    """Apparent RA and Dec in degrees from a Horizons quantity-2 row."""
    return float(row["R.A.__(a-app)"]), float(row["DEC___(a-app)"])


def body_differences(
    case: dict[str, Any], located: dict[str, str], appearance: dict[str, str] | None
) -> dict[str, float]:
    """Absolute differences between one bodies_apparent.json case and the Horizons rows."""
    d_ra, d_dec = sky_offsets_arcsec(
        case["ra_apparent_deg"], case["dec_apparent_deg"], horizons_position(located)
    )
    differences = {
        "ra": d_ra,
        "dec": d_dec,
        "distance": case["distance_au"] - float(located["delta"]),
    }
    if case["heliocentric_distance_au"] is not None:
        differences["helio"] = case["heliocentric_distance_au"] - float(located["r"])
    if appearance is not None:
        differences["illum"] = case["illuminated_fraction"] * 100.0 - float(appearance["Illu%"])
        differences["elong"] = case["elongation_deg"] - float(appearance["S-O-T"])
        differences["phase"] = case["phase_angle_deg"] - float(appearance["S-T-O"])
        magnitude = horizons_number(appearance, "APmag")
        if case["apparent_magnitude"] is not None and magnitude is not None:
            differences["mag"] = case["apparent_magnitude"] - magnitude
    return {name: abs(value) for name, value in differences.items()}


def check_bodies_against_horizons(cases: Sequence[dict[str, Any]]) -> None:
    """Compare every geocentric entry of bodies_apparent.json with Horizons at the same TT."""
    print("bodies_apparent.json vs Horizons, geocentric, same TT instants: maximum |difference|")
    print(
        '  body      n  RA*cos(dec)"  Dec"   dist AU     helio AU    illum %  elong deg  '
        "phase deg  mag"
    )
    for key in BODY_KEYS:
        mine = [case for case in cases if case["body"] == key]
        jds = [case["tt_jd"] for case in mine]
        position_command = HORIZONS_BARYCENTER.get(key, HORIZONS_CENTER[key])
        located = horizons_geocentric(position_command, jds, "2,19,20")
        appearance = None
        if key != "sun":
            appearance = horizons_geocentric(HORIZONS_CENTER[key], jds, "9,10,23,24")
        rows = [
            body_differences(case, located[i], None if appearance is None else appearance[i])
            for i, case in enumerate(mine)
        ]
        worst = {name: max(row[name] for row in rows) for name in rows[0]}
        print(
            f"  {key:9s}{len(mine):3d}  {worst['ra']:10.3f}  {worst['dec']:6.3f}  "
            f"{worst['distance']:9.2e}  {worst.get('helio', math.nan):9.2e}  "
            f"{worst.get('illum', math.nan):8.5f}  {worst.get('elong', math.nan):9.5f}  "
            f"{worst.get('phase', math.nan):9.5f}  {worst.get('mag', math.nan):.3f}"
        )


def print_offsets(label: str, moment: dt.datetime, d_ra: float, d_dec: float) -> None:
    """One line of the Horizons comparison: offsets in arcseconds at an instant."""
    print(f"  {label:5s} {moment:%Y-%m-%d %H:%M:%S}  dRA*cos(dec) {d_ra:+.3f}  dDec {d_dec:+.3f}")


def check_places_against_horizons(sky: Sky) -> None:
    """Moon and Mars apparent RA/Dec: Skyfield minus Horizons, geocentric and topocentric."""
    print("Apparent RA/Dec of date, Skyfield minus Horizons (quantity 2), arcseconds.")
    print("Geocentric, identical TT instants (independent of Delta T and Earth rotation):")
    moments = [
        dt.datetime(1955, 3, 4, 6, 0, 0),
        dt.datetime(1987, 4, 10, 19, 21, 0),
        J2000_NOON,
        TODAY,
        dt.datetime(2043, 8, 1, 18, 30, 0),
    ]
    times = [sky.time(moment) for moment in moments]
    for key in ("moon", "mars"):
        rows = horizons_geocentric(HORIZONS_CENTER[key], [float(t.tt) for t in times], "2")
        for moment, t, row in zip(moments, times, rows, strict=True):
            ra, dec, _ = sky.earth.at(t).observe(sky.body(key)).apparent().radec(epoch="date")
            d_ra, d_dec = sky_offsets_arcsec(ra.degrees, dec.degrees, horizons_position(row))
            print_offsets(key, moment, d_ra, d_dec)

    site = SITES[0]
    print(f"Topocentric from {site.key}, civil UTC on both sides (Delta T models differ slightly):")
    stamps = [dt.datetime(2026, 10, 17, 3, 0, 0), dt.datetime(2026, 10, 17, 9, 30, 0)]
    jds = [UNIX_EPOCH_JD + posix_seconds(m) / 86400.0 for m in stamps]
    for key in ("moon", "mars"):
        rows = horizons_geocentric(
            HORIZONS_CENTER[key],
            jds,
            "2",
            time_type="UT",
            CENTER="coord@399",
            COORD_TYPE="GEODETIC",
            SITE_COORD=horizons_site_coordinates(site),
        )
        for moment, row in zip(stamps, rows, strict=True):
            t = sky.ts.utc(
                moment.year, moment.month, moment.day, moment.hour, moment.minute, moment.second
            )
            ra, dec, _ = (
                sky.observer(site).at(t).observe(sky.body(key)).apparent().radec(epoch="date")
            )
            d_ra, d_dec = sky_offsets_arcsec(ra.degrees, dec.degrees, horizons_position(row))
            print_offsets(key, moment, d_ra, d_dec)


def horizons_site_coordinates(site: Site) -> str:
    """Horizons `SITE_COORD` text: east longitude (deg), latitude (deg), height (km)."""
    return f"{site.longitude},{site.latitude},{site.elevation_m / 1000.0}"


def horizons_rise_set_events(text: str) -> list[tuple[dt.datetime, str]]:
    """(time, 'r' or 's') for every rise/set row of a Horizons RTS-only table."""
    events = []
    for line in horizons_table(text):
        fields = line.split()
        if not re.match(r"\d{4}-[A-Za-z]{3}-\d{2}$", fields[0]):
            continue  # e.g. "No ephemeris ..." when the target never rises or sets
        flag = fields[2][-1]
        if flag in "rs":
            clock = "%H:%M:%S" if fields[1].count(":") == 2 else "%H:%M"
            events.append((dt.datetime.strptime(" ".join(fields[:2]), f"%Y-%b-%d {clock}"), flag))
    return events


def check_riseset_against_horizons(riseset: dict[str, Any]) -> None:
    """Compare 2026-10-17 rise/set crossings with Horizons' 1-minute rise/transit/set search."""
    print("Rise/set 2026-10-17 at boulder, sydney, tromso: Horizons 1-minute search (upper limb")
    print("of Sun and Moon on the geometric horizon after refraction) minus fixture, seconds.")
    print("Horizons reports an event in the minute before its printed time: 0..60 is agreement.")
    differences: dict[str, list[float]] = collections.defaultdict(list)
    for case in riseset["cases"]:
        if case["date"] != "2026-10-17" or case["site"] not in ("boulder", "sydney", "tromso"):
            continue
        site = next(s for s in RISE_SET_SITES if s.key == case["site"])
        for key in ("sun", "moon", "jupiter", "venus"):
            text = horizons_query(
                COMMAND=HORIZONS_CENTER[key],
                CENTER="coord@399",
                COORD_TYPE="GEODETIC",
                SITE_COORD=horizons_site_coordinates(site),
                START_TIME=case["window_start_utc"][:16].replace("T", " "),
                STOP_TIME=case["window_end_utc"][:16].replace("T", " "),
                STEP_SIZE="1m GEO",
                TIME_TYPE="UT",
                TIME_DIGITS="SECONDS",
                QUANTITIES="4",
                ANG_FORMAT="DEG",
            )
            variants = ("horizon", "horizon_upper_limb") if key == "moon" else ("horizon",)
            for event_time, flag in horizons_rise_set_events(text):
                kind = "rise" if flag == "r" else "set"
                stamp = posix_seconds(event_time)
                for variant in variants:
                    crossings = [
                        c["unix"]
                        for c in case["objects"][key][variant]["crossings"]
                        if c["kind"] == kind
                    ]
                    differences[f"{key} {variant}"].append(
                        stamp - min(crossings, key=lambda u: abs(u - stamp))
                    )
    for label, values in differences.items():
        print_range(label, values)


# ---------------------------------------------------------------------------------------
# US Naval Observatory spot check
# ---------------------------------------------------------------------------------------

USNO_API = "https://aa.usno.navy.mil/api"
USNO_PHASE_KINDS = {
    "New Moon": "new",
    "First Quarter": "first_quarter",
    "Full Moon": "full",
    "Last Quarter": "last_quarter",
}


def usno_get(path: str, **query: str) -> dict[str, Any]:
    """GET a JSON document from the US Naval Observatory API (HTTPS, fixed host)."""
    url = f"{USNO_API}/{path}?{urllib.parse.urlencode(query)}"
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def check_phases_against_usno(phases: Sequence[dict[str, Any]]) -> None:
    """Principal phases, 2024-2028: fixture minus USNO, which prints whole minutes."""
    print("Moon phases, fixture minus US Naval Observatory:")
    differences = []
    for year in range(PHASES_START.year, PHASES_END.year):
        for entry in usno_get("moon/phases/year", year=str(year))["phasedata"]:
            hour, minute = (int(part) for part in entry["time"].split(":"))
            reference = posix_seconds(
                dt.datetime(entry["year"], entry["month"], entry["day"], hour, minute)
            )
            kind = USNO_PHASE_KINDS[entry["phase"]]
            candidates = [p["unix"] - reference for p in phases if p["phase"] == kind]
            differences.append(min(candidates, key=abs))
    print_range("all phases", differences)


def usno_day_events(site: Site, day: dt.date) -> dict[tuple[str, str], list[float]]:
    """The USNO's events for one UT date as POSIX seconds, keyed by (body, phenomenon)."""
    coordinates = f"{site.latitude},{site.longitude}"
    data = usno_get("rstt/oneday", date=day.isoformat(), coords=coordinates, tz="0")
    midnight = posix_seconds(dt.datetime(day.year, day.month, day.day))
    events: dict[tuple[str, str], list[float]] = collections.defaultdict(list)
    for body, key in (("sun", "sundata"), ("moon", "moondata")):
        for entry in data["properties"]["data"].get(key, []):
            if entry.get("time"):
                hour, minute = (int(part) for part in entry["time"].split(":"))
                events[(body, entry["phen"])].append(midnight + 3600 * hour + 60 * minute)
    return events


def check_riseset_against_usno(riseset: dict[str, Any]) -> None:
    """Sun and Moon rise, set, civil twilight and transit: fixture minus USNO (whole minutes)."""
    print("Rise/set/transit of the Sun and Moon, fixture minus US Naval Observatory:")
    rules = (
        ("sun rise/set", "sun", "horizon", {"Rise": "rise", "Set": "set"}),
        (
            "sun civil twilight",
            "sun",
            "civil",
            {"Begin Civil Twilight": "rise", "End Civil Twilight": "set"},
        ),
        ("moon upper limb", "moon", "horizon_upper_limb", {"Rise": "rise", "Set": "set"}),
        ("moon as specified", "moon", "horizon", {"Rise": "rise", "Set": "set"}),
    )
    differences: dict[str, list[float]] = collections.defaultdict(list)
    skipped: collections.Counter[str] = collections.Counter()

    def compare(label: str, reference: list[float], mine: list[float]) -> None:
        if len(reference) == len(mine):
            differences[label].extend(m - r for m, r in zip(mine, sorted(reference), strict=True))
        else:
            skipped[label] += 1

    for case in riseset["cases"]:
        site = next(s for s in RISE_SET_SITES if s.key == case["site"])
        window_start = parse_iso_seconds(case["window_start_utc"])
        start, end = posix_seconds(window_start), posix_seconds(window_start) + 86400.0
        events: dict[tuple[str, str], list[float]] = collections.defaultdict(list)
        for offset in (0, 1):
            day_events = usno_day_events(site, window_start.date() + dt.timedelta(days=offset))
            for key, values in day_events.items():
                events[key].extend(values)
        for label, body, variant, phenomena in rules:
            for phenomenon, kind in phenomena.items():
                compare(
                    label,
                    [t for t in events[(body, phenomenon)] if start <= t < end],
                    [
                        c["unix"]
                        for c in case["objects"][body][variant]["crossings"]
                        if c["kind"] == kind
                    ],
                )
        for body in ("sun", "moon"):
            compare(
                f"{body} transit",
                [t for t in events[(body, "Upper Transit")] if start <= t < end],
                [t["unix"] for t in case["objects"][body]["transits"]],
            )
    for label, values in differences.items():
        print_range(label, values)
    for label, count in skipped.items():
        print(
            f"  {label}: {count} windows not compared (the USNO lists a different number of events)"
        )


def external_check(sky: Sky, out_dir: Path) -> None:
    """Compare Skyfield and the generated fixtures with JPL Horizons and the USNO."""

    def load(name: str) -> dict[str, Any]:
        return json.loads((out_dir / name).read_text(encoding="utf-8"))

    riseset = load("riseset.json")
    check_places_against_horizons(sky)
    check_bodies_against_horizons(load("bodies_apparent.json")["cases"])
    check_riseset_against_horizons(riseset)
    check_phases_against_usno(load("moon_phases.json")["phases"])
    check_riseset_against_usno(riseset)


# ---------------------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------------------

# (file name, builder, extra pretty-printing depth for the "cases" key)
BUILDERS: tuple[tuple[str, Callable[[Sky], dict[str, Any]], int], ...] = (
    ("sidereal.json", build_sidereal, 1),
    ("stars_apparent.json", build_stars, 1),
    ("bodies_apparent.json", build_bodies, 1),
    ("riseset.json", build_riseset, 3),
    ("moon_phases.json", build_moon_phases, 1),
)


def main(argv: Sequence[str] | None = None) -> int:
    """Generate the fixtures, or compare them with the external services."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help="where de440s.bsp is cached (default: %(default)s)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="where the JSON fixtures are written (default: %(default)s)",
    )
    parser.add_argument(
        "--external-check",
        action="store_true",
        help="compare the written fixtures with JPL Horizons and the US Naval "
        "Observatory instead of generating them",
    )
    args = parser.parse_args(argv)

    sky = load_sky(args.data_dir)
    if args.external_check:
        external_check(sky, args.out_dir)
        return 0

    documents = {filename: builder(sky) for filename, builder, _ in BUILDERS}
    check_ranges("stars_apparent", documents["stars_apparent.json"]["cases"])
    check_ranges("bodies_apparent", documents["bodies_apparent.json"]["cases"])
    crossing_s, transit_s = cross_check_riseset(sky, documents["riseset.json"])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for filename, _, depth in BUILDERS:
        text = render_document(documents[filename], {"cases": depth})
        (args.out_dir / filename).write_text(text, encoding="utf-8", newline="\n")
        data = text.encode("utf-8")
        print(f"{filename}: {len(data):,} bytes, sha256 {hashlib.sha256(data).hexdigest()}")
    print(
        "cross-check against skyfield.almanac: worst rise/set difference "
        f"{crossing_s:.3f} s, worst fixed-star transit difference {transit_s:.3f} s"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
