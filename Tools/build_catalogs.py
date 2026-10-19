#!/usr/bin/env python3
"""Builds the sky catalogs that ship inside Lodestar.

The script downloads open astronomical data files, each pinned (GitHub files to an immutable
commit, CDS/VizieR files to the URL) and verified against the sha256 digest recorded in
``sources.lock.json``, and converts them into the compact JSON resources bundled by ``LodestarKit``:

    stars.json           stars brighter than magnitude 6.5 plus every named star (HYG Database)
    dsos.json            the deep-sky catalog: Messier, Caldwell, bright and named NGC/IC objects
                         (OpenNGC), Sharpless 2 HII regions, Barnard and Lynds dark nebulae and
                         large Collinder/Melotte/Trumpler/Stock clusters (CDS/VizieR)
    constellations.json  the 88 IAU constellations: names, label positions, stick figures
    milkyway.json        five nested Milky Way brightness outlines (d3-celestial)

Run it from the repository root, always in isolated mode::

    python3 -I Tools/build_catalogs.py --out LodestarKit/Sources/LodestarKit/Resources \\
        --cache Tools/.cache

The output is deterministic: the same lock file always yields byte-identical files. Downloaded
content is only ever parsed with ``csv`` and ``json``; nothing from the network is executed or
evaluated. Every check in the "validation" section raises :class:`BuildError`, which makes the
script exit non-zero before any output file is touched.

Lock maintenance::

    --refresh-lock             re-resolve each source's ref to a commit, re-download, re-hash
    --refresh-lock --ref KEY=REF   additionally move one source to another branch or tag
    --refresh-lock --only KEY      refresh just the named sources and keep the rest of the lock
    --check                    build in memory and compare with ``--out`` instead of writing

Only the Python standard library is used. See ``Tools/README.md`` for the full documentation.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import datetime as dt
import gzip
import hashlib
import http.client
import json
import math
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterable, Iterator, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TypeVar

# ==========================================================================================
# Configuration
# ==========================================================================================

SCHEMA_VERSION = 1
LOCK_SCHEMA_VERSION = 1

# One catalog entry as it is serialized to JSON.
Item = dict[str, Any]
T = TypeVar("T")

USER_AGENT = "lodestar-build-catalogs/1"
GITHUB_API = "https://api.github.com"
RAW_CONTENT = "https://raw.githubusercontent.com"
CDS_FTP = "https://cdsarc.cds.unistra.fr/ftp/"
DOWNLOAD_TIMEOUT_SECONDS = 60
MAX_DOWNLOAD_BYTES = 128 * 1024 * 1024

# Stars: everything at or brighter than this visual magnitude, plus every named star.
STAR_MAGNITUDE_LIMIT = 6.5
SUN_HYG_ID = 0
HIPPARCOS_EPOCH = 1991.25
J2000_EPOCH = 2000.0

# Deep-sky objects, first selection ("legacy"): every Messier object, every named object, every
# other object with V <= 10.0 (or B <= 10.5 when V is unknown) and every large nebula without a
# magnitude. Everything this rule selects keeps prominence 3 or better, so no object of the first
# release can drop out of the browse lists (see ``dso_prominence``).
DSO_VISUAL_MAGNITUDE_LIMIT = 10.0
DSO_BLUE_MAGNITUDE_LIMIT = 10.5
# Large nebulae usually have no magnitude at all but are prime wide-field targets.
NEBULA_MIN_SIZE_ARCMIN = 10.0
NEBULA_TYPES = frozenset({"HII", "EmN", "RfN", "Neb", "SNR", "DrkN", "Cl+N"})
# Dup/NonEx are catalogue bookkeeping; Nova entries quote long-faded outburst magnitudes.
EXCLUDED_DSO_TYPES = frozenset({"Dup", "NonEx", "Nova"})
PLAIN_STAR_TYPES = frozenset({"*", "**"})
DSO_TYPES = frozenset(
    {"G", "OCl", "GCl", "PN", "HII", "EmN", "RfN", "Neb", "SNR", "DrkN", "Cl+N", "*Ass",
     "GPair", "GTrpl", "GGroup", "**", "*", "Other"}
)
MESSIER_COUNT = 110
CALDWELL_COUNT = 109

# Deep-sky objects, extended selection: what a photographer can reach with a camera lens or a
# small telescope. In addition to the first selection, every OpenNGC object that
#   - has V <= 11.5 (or B <= 12.0 when V is unknown), or
#   - is a nebula of any kind (NEBULA_TYPES) at least 3' across, or
#   - is an open cluster, cluster with nebulosity or association at least 30' across, or
#   - is a Caldwell object.
# Plain stars (`*`, `**`) only enter when they are Messier, Caldwell or named.
EXT_VISUAL_MAGNITUDE_LIMIT = 11.5
EXT_BLUE_MAGNITUDE_LIMIT = 12.0
EXT_NEBULA_MIN_SIZE_ARCMIN = 3.0
EXT_CLUSTER_MIN_SIZE_ARCMIN = 30.0
CLUSTER_TYPES = frozenset({"OCl", "Cl+N", "*Ass"})

# Lynds' dark nebulae (VizieR VII/7A): 1,791 clouds, far too many to draw. The cut keeps the
# darkest clouds (opacity class 6 of 1-6) and the large ones (at least a square degree), plus the
# few that have a popular name. An LDN cloud is drawn as a circle of the same area.
LYNDS_DARKEST_OPACITY = 6
LYNDS_MIN_AREA_SQUARE_DEGREES = 1.0

# Collinder, Melotte, Trumpler and Stock clusters from Dias et al. (VizieR B/ocl): only the
# large ones, which fill a camera-lens field and are easy to miss in a list of small clusters.
OPEN_CLUSTER_MIN_SIZE_ARCMIN = 60.0
# Beyond 10 degrees a "cluster" is a moving group (Collinder 285 is the Ursa Major group, 23
# degrees across), not something that is framed or found in the sky.
OPEN_CLUSTER_MAX_SIZE_ARCMIN = 600.0
OPEN_CLUSTER_CATALOGUES = {"Collinder": "Cl", "Melotte": "Mel", "Trumpler": "Tr", "Stock": "St"}

# Prominence: how conspicuous an object is among deep-sky objects, from 1 (showpiece) to 4
# (obscure). The rules are in ``dso_prominence``; the thresholds are here.
PROMINENCE_SHOWPIECE_MAGNITUDE = 4.0
PROMINENCE_BRIGHT_MAGNITUDE = 8.0
PROMINENCE_NOTABLE_MAGNITUDE = 10.0
PROMINENCE_LARGE_NEBULA_ARCMIN = 60.0
PROMINENCE_NOTABLE_NEBULA_ARCMIN = 10.0
PROMINENCE_NOTABLE_CLUSTER_ARCMIN = 30.0
PROMINENCE_LARGE_DARK_ARCMIN = 180.0
PROMINENCE_NOTABLE_DARK_ARCMIN = 60.0
LYNDS_NOTABLE_OPAQUE_ARCMIN = 20.0
SHARPLESS_NOTABLE_ARCMIN = 30.0
SHARPLESS_BRIGHT_NOTABLE_ARCMIN = 10.0
PROMINENCE_RANGE = (1, 4)

# Reference epochs for precession (Julian dates): B1875.0 is the equinox of the IAU constellation
# boundaries, B1900.0 and B1950.0 are the equinoxes of the Sharpless and Lynds positions.
JD_J2000 = 2451545.0
JD_B1875 = 2405889.25855
JD_B1900 = 2415020.31352
JD_B1950 = 2433282.4235

# Hipparcos positions at epoch J2000.0 (ESA 1997, propagated with its proper motions; VizieR
# I/239), as (right ascension, declination) in degrees. They pin the epoch handling of HYG.
REFERENCE_STARS = {
    32349: (101.287155, -16.716116),  # Sirius
    11767: (37.954515, 89.264110),    # Polaris
    70890: (217.428953, -62.679484),  # Proxima Centauri
    71683: (219.902066, -60.833975),  # Rigil Kentaurus
    87937: (269.452077, 4.693388),    # Barnard's Star
}
REFERENCE_TOLERANCE_DEGREES = 2e-5

# Messier's M102 is a known ambiguity: OpenNGC (following NED) lists it as a duplicate
# observation of M101, whereas many atlases and planetarium programs identify it with the
# Spindle Galaxy, NGC 5866. Adopting the latter keeps the Messier list complete.
MESSIER_OVERRIDES = {102: "NGC5866"}

# Popular names that OpenNGC lacks, and short forms people search for: OpenNGC row name ->
# (expected OpenNGC constellation, names). The names come first, in the given order, followed
# by OpenNGC's own; acronyms such as "LMC" are always moved behind the full names. Each entry
# is checked against the data, so a mistyped designation fails the build instead of attaching
# a name to the wrong object.
SUPPLEMENTARY_NAMES: dict[str, tuple[str, tuple[str, ...]]] = {
    "ESO056-115": ("Dor", ("LMC",)),
    "NGC0292": ("Tuc", ("SMC",)),
    "Mel022": ("Tau", ("Pleiades", "Seven Sisters")),
    "NGC0253": ("Scl", ("Sculptor Galaxy",)),
    "NGC0281": ("Cas", ("Pacman Nebula",)),
    "NGC0628": ("Psc", ("Phantom Galaxy",)),
    "NGC1912": ("Aur", ("Starfish Cluster",)),
    "NGC1960": ("Aur", ("Pinwheel Cluster",)),
    "NGC2024": ("Ori", ("Flame Nebula",)),
    "NGC2359": ("CMa", ("Thor's Helmet",)),
    "NGC2516": ("Car", ("Southern Beehive Cluster",)),
    "NGC3628": ("Leo", ("Hamburger Galaxy",)),
    "NGC5457": ("UMa", ("Pinwheel Galaxy",)),
    "NGC6334": ("Sco", ("Cat's Paw Nebula",)),
    "NGC6656": ("Sgr", ("Great Sagittarius Cluster",)),
    "NGC7380": ("Cep", ("Wizard Nebula",)),
    "IC1396": ("Cep", ("Elephant's Trunk Nebula",)),
    "IC1805": ("Cas", ("Heart Nebula",)),
    "IC1848": ("Cas", ("Soul Nebula",)),
    "IC2177": ("Mon", ("Seagull Nebula",)),
    "IC2602": ("Car", ("Southern Pleiades",)),
    "IC2944": ("Cen", ("Running Chicken Nebula",)),
    "IC4628": ("Sco", ("Prawn Nebula",)),
}

# OpenNGC names that belong to another object: the Flame Nebula is NGC 2024, not IC 434, the
# emission strip behind the Horsehead. Each name must still be present, so the entry is dropped
# once upstream fixes it.
REMOVED_NAMES = {"IC0434": ("Flame Nebula",)}

# Targets that must survive the selection (checked by designation or by name).
REQUIRED_DSOS: tuple[tuple[str, int | str], ...] = (
    ("name", "Large Magellanic Cloud"), ("name", "Small Magellanic Cloud"),
    ("name", "Pleiades"), ("name", "Hyades"), ("name", "Coma Star Cluster"),
    ("name", "Horsehead Nebula"), ("name", "Carina Nebula"), ("name", "North America Nebula"),
    ("name", "Helix Nebula"), ("name", "Lagoon Nebula"), ("name", "Orion Nebula"),
    ("name", "Andromeda Galaxy"), ("name", "Triangulum Galaxy"),
    ("NGC", 869), ("NGC", 884), ("NGC", 5139), ("NGC", 104), ("NGC", 3372), ("NGC", 7000),
    ("NGC", 2237), ("NGC", 2244), ("NGC", 6960), ("NGC", 6992), ("NGC", 7293), ("IC", 434),
    ("NGC", 2024), ("NGC", 281), ("IC", 1396), ("IC", 1805), ("IC", 1848),
)

# Milky Way outlines.
MILKY_WAY_TOLERANCE_DEGREES = 0.25
MILKY_WAY_MAX_BYTES = 200 * 1024
MILKY_WAY_DECIMALS = 3
MILKY_WAY_SEAM_STEP_DEGREES = 2.0
MAX_ARC_CHORD_DEGREES = 60.0

GREEK_LETTERS = {
    "Alp": "α", "Bet": "β", "Gam": "γ", "Del": "δ", "Eps": "ε", "Zet": "ζ", "Eta": "η",
    "The": "θ", "Iot": "ι", "Kap": "κ", "Lam": "λ", "Mu": "μ", "Nu": "ν", "Xi": "ξ",
    "Omi": "ο", "Pi": "π", "Rho": "ρ", "Sig": "σ", "Tau": "τ", "Ups": "υ", "Phi": "φ",
    "Chi": "χ", "Psi": "ψ", "Ome": "ω",
}
SUPERSCRIPT_DIGITS = str.maketrans("0123456789", "⁰¹²³⁴⁵⁶⁷⁸⁹")

# OpenNGC splits Serpens into two parts; both belong to the single IAU constellation Ser.
OPENNGC_CONSTELLATION_ALIASES = {"se1": "Ser", "se2": "Ser"}

# The 88 IAU constellations: (abbreviation, name, genitive). This table is authoritative.
# d3-celestial is cross-checked against it and has two known errors (see below).
IAU_CONSTELLATIONS: tuple[tuple[str, str, str], ...] = (
    ("And", "Andromeda", "Andromedae"), ("Ant", "Antlia", "Antliae"),
    ("Aps", "Apus", "Apodis"), ("Aqr", "Aquarius", "Aquarii"),
    ("Aql", "Aquila", "Aquilae"), ("Ara", "Ara", "Arae"),
    ("Ari", "Aries", "Arietis"), ("Aur", "Auriga", "Aurigae"),
    ("Boo", "Boötes", "Boötis"), ("Cae", "Caelum", "Caeli"),
    ("Cam", "Camelopardalis", "Camelopardalis"), ("Cnc", "Cancer", "Cancri"),
    ("CVn", "Canes Venatici", "Canum Venaticorum"), ("CMa", "Canis Major", "Canis Majoris"),
    ("CMi", "Canis Minor", "Canis Minoris"), ("Cap", "Capricornus", "Capricorni"),
    ("Car", "Carina", "Carinae"), ("Cas", "Cassiopeia", "Cassiopeiae"),
    ("Cen", "Centaurus", "Centauri"), ("Cep", "Cepheus", "Cephei"),
    ("Cet", "Cetus", "Ceti"), ("Cha", "Chamaeleon", "Chamaeleontis"),
    ("Cir", "Circinus", "Circini"), ("Col", "Columba", "Columbae"),
    ("Com", "Coma Berenices", "Comae Berenices"), ("CrA", "Corona Australis", "Coronae Australis"),
    ("CrB", "Corona Borealis", "Coronae Borealis"), ("Crv", "Corvus", "Corvi"),
    ("Crt", "Crater", "Crateris"), ("Cru", "Crux", "Crucis"),
    ("Cyg", "Cygnus", "Cygni"), ("Del", "Delphinus", "Delphini"),
    ("Dor", "Dorado", "Doradus"), ("Dra", "Draco", "Draconis"),
    ("Equ", "Equuleus", "Equulei"), ("Eri", "Eridanus", "Eridani"),
    ("For", "Fornax", "Fornacis"), ("Gem", "Gemini", "Geminorum"),
    ("Gru", "Grus", "Gruis"), ("Her", "Hercules", "Herculis"),
    ("Hor", "Horologium", "Horologii"), ("Hya", "Hydra", "Hydrae"),
    ("Hyi", "Hydrus", "Hydri"), ("Ind", "Indus", "Indi"),
    ("Lac", "Lacerta", "Lacertae"), ("Leo", "Leo", "Leonis"),
    ("LMi", "Leo Minor", "Leonis Minoris"), ("Lep", "Lepus", "Leporis"),
    ("Lib", "Libra", "Librae"), ("Lup", "Lupus", "Lupi"),
    ("Lyn", "Lynx", "Lyncis"), ("Lyr", "Lyra", "Lyrae"),
    ("Men", "Mensa", "Mensae"), ("Mic", "Microscopium", "Microscopii"),
    ("Mon", "Monoceros", "Monocerotis"), ("Mus", "Musca", "Muscae"),
    ("Nor", "Norma", "Normae"), ("Oct", "Octans", "Octantis"),
    ("Oph", "Ophiuchus", "Ophiuchi"), ("Ori", "Orion", "Orionis"),
    ("Pav", "Pavo", "Pavonis"), ("Peg", "Pegasus", "Pegasi"),
    ("Per", "Perseus", "Persei"), ("Phe", "Phoenix", "Phoenicis"),
    ("Pic", "Pictor", "Pictoris"), ("Psc", "Pisces", "Piscium"),
    ("PsA", "Piscis Austrinus", "Piscis Austrini"), ("Pup", "Puppis", "Puppis"),
    ("Pyx", "Pyxis", "Pyxidis"), ("Ret", "Reticulum", "Reticuli"),
    ("Sge", "Sagitta", "Sagittae"), ("Sgr", "Sagittarius", "Sagittarii"),
    ("Sco", "Scorpius", "Scorpii"), ("Scl", "Sculptor", "Sculptoris"),
    ("Sct", "Scutum", "Scuti"), ("Ser", "Serpens", "Serpentis"),
    ("Sex", "Sextans", "Sextantis"), ("Tau", "Taurus", "Tauri"),
    ("Tel", "Telescopium", "Telescopii"), ("Tri", "Triangulum", "Trianguli"),
    ("TrA", "Triangulum Australe", "Trianguli Australis"), ("Tuc", "Tucana", "Tucanae"),
    ("UMa", "Ursa Major", "Ursae Majoris"), ("UMi", "Ursa Minor", "Ursae Minoris"),
    ("Vel", "Vela", "Velorum"), ("Vir", "Virgo", "Virginis"),
    ("Vol", "Volans", "Volantis"), ("Vul", "Vulpecula", "Vulpeculae"),
)
# Deviations of d3-celestial from the IAU table that are known and corrected here. Any other
# deviation fails the build so a data refresh cannot silently introduce one.
KNOWN_D3_DEVIATIONS = {
    "CrA": {"name": "Corona Austrina", "gen": "Coronae Austrini"},
    "Cru": {"gen": "Crux"},
}
# d3-celestial lists Serpens as two features that share the id "Ser"; the first part listed
# here supplies the label position.
SPLIT_CONSTELLATIONS = {"Ser": ("Serpens Caput", "Serpens Cauda")}


# ==========================================================================================
# Errors and small helpers
# ==========================================================================================

class BuildError(Exception):
    """An input was unusable or a validation failed; the message says what and why."""


def require(condition: bool, message: str) -> None:
    """Raises :class:`BuildError` with ``message`` unless ``condition`` holds."""
    if not condition:
        raise BuildError(message)


def present(value: T | None, message: str) -> T:
    """Returns ``value``, or raises :class:`BuildError` with ``message`` if it is ``None``."""
    if value is None:
        raise BuildError(message)
    return value


def warn(message: str) -> None:
    """Prints a non-fatal diagnostic to stderr."""
    print(f"warning: {message}", file=sys.stderr)


_DECIMAL = re.compile(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_CONTROL_CHARACTERS = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def parse_float(raw: str, what: str) -> float | None:
    """Parses a plain decimal number; returns ``None`` for an empty field."""
    text = raw.strip()
    if not text:
        return None
    require(_DECIMAL.fullmatch(text) is not None, f"{what}: not a decimal number: {raw!r}")
    value = float(text)
    require(math.isfinite(value), f"{what}: not finite: {raw!r}")
    return value


def parse_int(raw: str, what: str) -> int | None:
    """Parses a non-negative integer; returns ``None`` for an empty field."""
    text = raw.strip()
    if not text:
        return None
    require(re.fullmatch(r"\d{1,9}", text) is not None, f"{what}: not an integer: {raw!r}")
    return int(text)


def clean_text(raw: str, what: str) -> str:
    """Normalizes text to NFC with single spaces; rejects control characters."""
    text = " ".join(unicodedata.normalize("NFC", raw).split())
    require(_CONTROL_CHARACTERS.search(text) is None, f"{what}: control character in {raw!r}")
    return text


def rounded(value: float, places: int) -> float:
    """Rounds to ``places`` decimals, never returning negative zero."""
    return round(value, places) + 0.0


def wrap_degrees(value: float) -> float:
    """Folds an angle into [0, 360)."""
    return value % 360.0


def require_range(value: float, low: float, high: float, what: str,
                  *, upper_open: bool = False) -> None:
    """Checks that ``value`` lies in ``[low, high]`` (or ``[low, high)``)."""
    inside = low <= value < high if upper_open else low <= value <= high
    require(inside, f"{what}: {value} outside [{low}, {high}{')' if upper_open else ']'}")


_SEXAGESIMAL = re.compile(r"([+-]?)(\d{1,3}):(\d{2}):(\d{2}(?:\.\d+)?)")


def parse_sexagesimal(raw: str, what: str) -> float:
    """Returns the decimal value of ``[+-]DD:MM:SS.s`` (hours or degrees, by context)."""
    match = present(_SEXAGESIMAL.fullmatch(raw.strip()),
                    f"{what}: not a sexagesimal value: {raw!r}")
    sign = -1.0 if match.group(1) == "-" else 1.0
    whole, minutes, seconds = int(match.group(2)), int(match.group(3)), float(match.group(4))
    require(minutes < 60 and seconds < 60.0, f"{what}: minutes or seconds out of range: {raw!r}")
    return sign * (whole + minutes / 60.0 + seconds / 3600.0)


def right_ascension_degrees(raw: str, what: str) -> float:
    """Converts ``HH:MM:SS.s`` to degrees in [0, 360)."""
    hours = parse_sexagesimal(raw, what)
    require_range(hours, 0.0, 24.0, f"{what} (hours)", upper_open=True)
    return hours * 15.0


def declination_degrees(raw: str, what: str) -> float:
    """Converts ``±DD:MM:SS.s`` to degrees in [-90, 90]."""
    degrees = parse_sexagesimal(raw, what)
    require_range(degrees, -90.0, 90.0, f"{what} (degrees)")
    return degrees


# ------------------------------------------------------------------------------------------
# JSON output
# ------------------------------------------------------------------------------------------

def format_number(value: float) -> str:
    """Formats a pre-rounded float with at most six decimals and no exponent."""
    require(math.isfinite(value), f"cannot serialize non-finite number {value!r}")
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def dumps(value: object) -> str:
    """Serializes JSON-compatible data compactly: no spaces, plain decimals, UTF-8 text."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format_number(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(dumps(item) for item in value) + "]"
    if isinstance(value, dict):
        members = (f"{json.dumps(key)}:{dumps(item)}" for key, item in value.items())
        return "{" + ",".join(members) + "}"
    raise TypeError(f"cannot serialize {type(value).__name__}")


def render_document(header: Mapping[str, object], list_key: str, items: Sequence[object]) -> bytes:
    """Renders ``{header..., list_key: [items...]}`` with one item per line."""
    opening = dumps(dict(header))[:-1]
    body = ",\n".join(dumps(item) for item in items)
    return f"{opening},{json.dumps(list_key)}:[\n{body}\n]}}\n".encode("utf-8")


# ==========================================================================================
# Upstream sources, lock file and downloads
# ==========================================================================================

@dataclass(frozen=True)
class SourceFile:
    """One file of an upstream repository. ``role`` is ``data`` or ``legal``.

    Legal files (licenses, readmes with credits) are hashed too, so a refresh can tell when the
    upstream terms or attributions changed and need a human review.
    """

    path: str
    role: str


@dataclass(frozen=True)
class Source:
    """An upstream data source: a GitHub repository (``kind`` "github", pinned to a commit) or a
    CDS/VizieR catalogue directory (``kind`` "cds", pinned to the sha256 of each file).

    For a GitHub source ``repo`` and ``default_ref`` say where the files come from; for a CDS source
    ``base_url`` is the directory under :data:`CDS_FTP` and ``license_id`` a short description of
    the terms, since CDS catalogues carry no SPDX license.
    """

    key: str
    title: str
    repo: str
    default_ref: str
    license_id: str
    files: tuple[SourceFile, ...]
    kind: str = "github"
    base_url: str = ""


# The terms CDS publishes for catalogues without a license of their own (see the licence page of
# VizieR): free of usage in a scientific context, original authors and publication cited, a
# VizieR acknowledgement appreciated; commercial use depends on the origin of the catalogue.
CDS_TERMS = "CDS-VizieR-terms"

SOURCES: tuple[Source, ...] = (
    Source(
        key="hyg",
        title="HYG Database v4.1",
        repo="astronexus/HYG-Database",
        default_ref="main",
        license_id="CC-BY-SA-4.0",
        files=(
            SourceFile("hyg/CURRENT/hygdata_v41.csv", "data"),
            SourceFile("hyg/CURRENT/LICENSE", "legal"),
            SourceFile("hyg/README.md", "legal"),
        ),
    ),
    Source(
        key="openngc",
        title="OpenNGC",
        repo="mattiaverga/OpenNGC",
        default_ref="v20260501",
        license_id="CC-BY-SA-4.0",
        files=(
            SourceFile("database_files/NGC.csv", "data"),
            SourceFile("database_files/addendum.csv", "data"),
            SourceFile(".reuse/dep5", "legal"),
            SourceFile("LICENSES/CC-BY-SA-4.0.txt", "legal"),
            SourceFile("README.md", "legal"),
        ),
    ),
    Source(
        key="d3celestial",
        title="d3-celestial",
        repo="ofrohn/d3-celestial",
        default_ref="master",
        license_id="BSD-3-Clause",
        files=(
            SourceFile("data/constellations.json", "data"),
            SourceFile("data/constellations.lines.json", "data"),
            SourceFile("data/mw.json", "data"),
            SourceFile("LICENSE", "legal"),
            SourceFile("readme.md", "legal"),
        ),
    ),
    Source(
        key="sharpless",
        title="Catalogue of HII Regions (Sharpless 1959), CDS VII/20",
        repo="",
        default_ref="",
        license_id=CDS_TERMS,
        files=(
            SourceFile("catalog.dat.gz", "data"),
            SourceFile("ReadMe", "legal"),
        ),
        kind="cds",
        base_url=CDS_FTP + "VII/20",
    ),
    Source(
        key="barnard",
        title="Barnard's Catalogue of 349 Dark Objects in the Sky (Barnard 1927), CDS VII/220A",
        repo="",
        default_ref="",
        license_id=CDS_TERMS,
        files=(
            SourceFile("barnard.dat", "data"),
            SourceFile("ReadMe", "legal"),
        ),
        kind="cds",
        base_url=CDS_FTP + "VII/220A",
    ),
    Source(
        key="lynds",
        title="Lynds' Catalogue of Dark Nebulae (Lynds 1962), CDS VII/7A",
        repo="",
        default_ref="",
        license_id=CDS_TERMS,
        files=(
            SourceFile("ldn", "data"),
            SourceFile("ReadMe", "legal"),
        ),
        kind="cds",
        base_url=CDS_FTP + "VII/7A",
    ),
    Source(
        key="dias",
        title="Optically visible open clusters and candidates, v3.5 (Dias et al. 2002), CDS B/ocl",
        repo="",
        default_ref="",
        license_id=CDS_TERMS,
        files=(
            SourceFile("clusters.dat", "data"),
            SourceFile("ReadMe", "legal"),
        ),
        kind="cds",
        base_url=CDS_FTP + "B/ocl",
    ),
    Source(
        key="roman",
        title="Identification of a constellation from a position (Roman 1987), CDS VI/42",
        repo="",
        default_ref="",
        license_id=CDS_TERMS,
        files=(
            SourceFile("data.dat", "data"),
            SourceFile("ReadMe", "legal"),
        ),
        kind="cds",
        base_url=CDS_FTP + "VI/42",
    ),
)
SOURCES_BY_KEY = {source.key: source for source in SOURCES}

HYG_CSV = ("hyg", "hyg/CURRENT/hygdata_v41.csv")
OPENNGC_CSV = ("openngc", "database_files/NGC.csv")
OPENNGC_ADDENDUM_CSV = ("openngc", "database_files/addendum.csv")
D3_CONSTELLATIONS = ("d3celestial", "data/constellations.json")
D3_LINES = ("d3celestial", "data/constellations.lines.json")
D3_MILKY_WAY = ("d3celestial", "data/mw.json")
SHARPLESS_DAT = ("sharpless", "catalog.dat.gz")
BARNARD_DAT = ("barnard", "barnard.dat")
LYNDS_DAT = ("lynds", "ldn")
DIAS_DAT = ("dias", "clusters.dat")
ROMAN_DAT = ("roman", "data.dat")


@dataclass(frozen=True)
class LockedFile:
    """The pinned digest of one source file."""

    role: str
    sha256: str
    size: int


@dataclass(frozen=True)
class LockedSource:
    """A source resolved to an immutable commit (GitHub) or to a directory URL (CDS).

    A CDS source has no ``repo``, ``ref`` or ``commit``; ``url`` is its directory and ``retrieved``
    the day its files were hashed, since the files cannot be addressed by a commit.
    """

    title: str
    repo: str
    ref: str
    commit: str
    license_id: str
    files: Mapping[str, LockedFile]
    url: str = ""
    retrieved: str = ""


@dataclass(frozen=True)
class Lock:
    """The contents of ``sources.lock.json``."""

    locked_on: str
    sources: Mapping[str, LockedSource]


_COMMIT = re.compile(r"[0-9a-f]{40}")
_SHA256 = re.compile(r"[0-9a-f]{64}")
_REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
_REF = re.compile(r"[A-Za-z0-9._-]{1,100}")
_REPO_PATH = re.compile(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*")
_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
_CDS_DIRECTORY = re.compile(r"[A-Za-z]+(?:/[A-Za-z0-9]+)+")


def check_repo_path(path: str) -> None:
    """Rejects anything but a plain relative path inside a repository."""
    require(_REPO_PATH.fullmatch(path) is not None, f"unsafe repository path: {path!r}")
    require(all(part not in (".", "..") for part in path.split("/")),
            f"unsafe repository path: {path!r}")


def lock_to_json(lock: Lock) -> str:
    """Serializes a lock file (stable key order, trailing newline)."""
    sources: dict[str, object] = {}
    for source in SOURCES:
        entry = lock.sources[source.key]
        files = {
            path: {"role": f.role, "sha256": f.sha256, "bytes": f.size}
            for path, f in entry.files.items()
        }
        if source.kind == "cds":
            sources[source.key] = {
                "title": entry.title,
                "url": entry.url,
                "license": entry.license_id,
                "retrieved": entry.retrieved,
                "files": files,
            }
        else:
            sources[source.key] = {
                "title": entry.title,
                "repo": entry.repo,
                "ref": entry.ref,
                "commit": entry.commit,
                "license": entry.license_id,
                "files": files,
            }
    document = {"schema": LOCK_SCHEMA_VERSION, "lockedOn": lock.locked_on, "sources": sources}
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def read_lock(path: Path, *, allow_missing: bool = False) -> Lock:
    """Reads and strictly validates the lock file against :data:`SOURCES`.

    With ``allow_missing`` sources the file lacks are left out instead of being an error, which
    lets ``--refresh-lock`` add a new source to an older lock.
    """
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise BuildError(f"cannot read lock file {path}: {error}") from error
    require(isinstance(document, dict) and document.get("schema") == LOCK_SCHEMA_VERSION,
            f"{path}: unsupported lock schema")
    locked_on = document.get("lockedOn")
    require(isinstance(locked_on, str) and _DATE.fullmatch(locked_on) is not None,
            f"{path}: lockedOn must be YYYY-MM-DD")
    raw_sources = document.get("sources")
    require(isinstance(raw_sources, dict)
            and (set(raw_sources) <= set(SOURCES_BY_KEY) if allow_missing
                 else set(raw_sources) == set(SOURCES_BY_KEY)),
            f"{path}: sources do not match the script; run with --refresh-lock")
    sources: dict[str, LockedSource] = {}
    for source in SOURCES:
        if allow_missing and source.key not in raw_sources:
            continue
        raw = raw_sources[source.key]
        require(isinstance(raw, dict), f"{path}: malformed entry for {source.key}")
        require(raw.get("license") == source.license_id and raw.get("title") == source.title,
                f"{path}: {source.key} metadata differs from the script; run --refresh-lock")
        ref, commit, url, retrieved = "", "", "", ""
        if source.kind == "cds":
            url, retrieved = raw.get("url"), raw.get("retrieved")
            require(url == source.base_url,
                    f"{path}: {source.key} url differs from the script; run --refresh-lock")
            require(isinstance(retrieved, str) and _DATE.fullmatch(retrieved) is not None,
                    f"{path}: {source.key}: retrieved must be YYYY-MM-DD")
        else:
            require(raw.get("repo") == source.repo,
                    f"{path}: {source.key} metadata differs from the script; run --refresh-lock")
            ref, commit = raw.get("ref"), raw.get("commit")
            require(isinstance(ref, str) and _REF.fullmatch(ref) is not None,
                    f"{path}: {source.key}: bad ref")
            require(isinstance(commit, str) and _COMMIT.fullmatch(commit) is not None,
                    f"{path}: {source.key}: commit must be a full 40-digit SHA-1")
        raw_files = raw.get("files")
        require(isinstance(raw_files, dict)
                and list(raw_files) == [f.path for f in source.files],
                f"{path}: {source.key}: file list differs from the script; run --refresh-lock")
        files: dict[str, LockedFile] = {}
        for source_file in source.files:
            item = raw_files[source_file.path]
            require(isinstance(item, dict) and item.get("role") == source_file.role,
                    f"{path}: {source.key}/{source_file.path}: bad role")
            digest, size = item.get("sha256"), item.get("bytes")
            require(isinstance(digest, str) and _SHA256.fullmatch(digest) is not None,
                    f"{path}: {source.key}/{source_file.path}: bad sha256")
            require(isinstance(size, int) and not isinstance(size, bool)
                    and 0 < size <= MAX_DOWNLOAD_BYTES,
                    f"{path}: {source.key}/{source_file.path}: bad size")
            files[source_file.path] = LockedFile(source_file.role, digest, size)
        sources[source.key] = LockedSource(source.title, source.repo, ref, commit,
                                           source.license_id, files, url, retrieved)
    return Lock(locked_on, sources)


class _HttpsOnlyRedirects(urllib.request.HTTPRedirectHandler):
    """Refuses to follow a redirect that would leave TLS."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require(newurl.startswith("https://"), f"refusing non-HTTPS redirect to {newurl}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_HttpsOnlyRedirects)


def _open(url: str, accept: str | None = None) -> http.client.HTTPResponse:
    headers = {"User-Agent": USER_AGENT}
    if accept:
        headers["Accept"] = accept
    return _OPENER.open(urllib.request.Request(url, headers=headers),
                        timeout=DOWNLOAD_TIMEOUT_SECONDS)


def resolve_commit(repo: str, ref: str) -> str:
    """Resolves a branch or tag of a GitHub repository to its commit SHA via the GitHub API."""
    require(_REPO.fullmatch(repo) is not None and _REF.fullmatch(ref) is not None,
            f"bad repository or ref: {repo}@{ref}")
    url = f"{GITHUB_API}/repos/{repo}/commits/{urllib.parse.quote(ref, safe='')}"
    try:
        with _open(url, "application/vnd.github+json") as response:
            payload = json.loads(response.read(1_000_000))
    except (OSError, http.client.HTTPException, ValueError) as error:
        raise BuildError(f"cannot resolve {repo}@{ref}: {error}") from error
    sha = payload.get("sha") if isinstance(payload, dict) else None
    require(isinstance(sha, str) and _COMMIT.fullmatch(sha) is not None,
            f"GitHub returned no commit SHA for {repo}@{ref}")
    return sha


def raw_url(repo: str, commit: str, path: str) -> str:
    """The immutable raw-content URL of a file at a commit."""
    check_repo_path(path)
    require(_REPO.fullmatch(repo) is not None and _COMMIT.fullmatch(commit) is not None,
            f"bad repository or commit: {repo}@{commit}")
    return f"{RAW_CONTENT}/{repo}/{commit}/{urllib.parse.quote(path)}"


def cds_url(base_url: str, path: str) -> str:
    """The URL of a file in a CDS catalogue directory (HTTPS only, below :data:`CDS_FTP`)."""
    check_repo_path(path)
    require(base_url.startswith(CDS_FTP) and _CDS_DIRECTORY.fullmatch(base_url[len(CDS_FTP):])
            is not None, f"bad CDS directory: {base_url}")
    return f"{base_url}/{urllib.parse.quote(path)}"


def source_url(source: Source, entry: LockedSource, path: str) -> str:
    """Where a file of a source is downloaded from."""
    if source.kind == "cds":
        return cds_url(entry.url, path)
    return raw_url(entry.repo, entry.commit, path)


def download(url: str, destination: Path, max_bytes: int) -> tuple[str, int]:
    """Streams ``url`` into ``destination``; returns the sha256 digest and the byte count."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + ".part")
    digest, size = hashlib.sha256(), 0
    try:
        with _open(url) as response, partial.open("wb") as output:
            require(response.status == 200, f"{url}: HTTP {response.status}")
            while chunk := response.read(1 << 20):
                size += len(chunk)
                require(size <= max_bytes, f"{url}: larger than the expected {max_bytes} bytes")
                digest.update(chunk)
                output.write(chunk)
    except (OSError, http.client.HTTPException) as error:
        partial.unlink(missing_ok=True)
        raise BuildError(f"download failed for {url}: {error}") from error
    except BuildError:
        partial.unlink(missing_ok=True)
        raise
    os.replace(partial, destination)
    return digest.hexdigest(), size


def sha256_of(path: Path) -> str:
    """The sha256 digest of a file, read in chunks."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def cache_path(cache: Path, key: str, commit: str, path: str) -> Path:
    """Where a source file is cached: ``<cache>/<source>/<commit>/<repo path>``.

    CDS sources have no commit; their folder is called ``cds`` and a cached file is trusted only
    when its sha256 digest matches the lock.
    """
    check_repo_path(path)
    return cache / key / commit / path


def cache_version(entry: LockedSource) -> str:
    """The cache folder of a source: its commit, or ``cds`` for a CDS directory."""
    return entry.commit or "cds"


def fetch_locked_files(lock: Lock, cache: Path) -> dict[tuple[str, str], Path]:
    """Makes every locked file available in the cache, verifying each against the lock.

    A cached copy is reused only when its digest matches; anything else is downloaded again.
    A download whose digest differs from the lock is deleted and reported: it means upstream
    rewrote history or replaced a file, the lock is stale, or the transfer was tampered with.
    """
    paths: dict[tuple[str, str], Path] = {}
    for source in SOURCES:
        entry = lock.sources[source.key]
        for path, locked in entry.files.items():
            destination = cache_path(cache, source.key, cache_version(entry), path)
            if destination.is_file() and sha256_of(destination) == locked.sha256:
                paths[(source.key, path)] = destination
                continue
            print(f"downloading {source.key}: {path}", file=sys.stderr)
            digest, size = download(source_url(source, entry, path), destination, locked.size + 1)
            if digest != locked.sha256 or size != locked.size:
                destination.unlink(missing_ok=True)
                where = f"at commit {entry.commit}" if entry.commit else f"from {entry.url}"
                raise BuildError(
                    f"{source.key}/{path}: sha256 {digest} ({size} bytes) differs from the lock "
                    f"({locked.sha256}, {locked.size} bytes) {where}")
            paths[(source.key, path)] = destination
    return paths


def refresh_lock(previous: Lock | None, overrides: Mapping[str, str], cache: Path,
                 only: Sequence[str] = ()) -> Lock:
    """Re-resolves every source to a commit, downloads its files and records their digests.

    With ``only``, just those sources are refreshed; the others, and the date of the lock, are
    taken over from ``previous`` unchanged, so output built from them stays byte for byte the
    same. Sources the previous lock does not know are always refreshed.
    """
    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    refreshed_all = not only
    sources: dict[str, LockedSource] = {}
    for source in SOURCES:
        old = previous.sources.get(source.key) if previous else None
        if only and source.key not in only and old is not None:
            sources[source.key] = old
            continue
        if source.kind == "cds":
            ref, commit = "", ""
            version = "cds"
        else:
            ref = overrides.get(source.key) or (old.ref if old else source.default_ref)
            commit = resolve_commit(source.repo, ref)
            version = commit
        files: dict[str, LockedFile] = {}
        for source_file in source.files:
            print(f"downloading {source.key}@{version[:10]}: {source_file.path}", file=sys.stderr)
            destination = cache_path(cache, source.key, version, source_file.path)
            if source.kind == "cds":
                url = cds_url(source.base_url, source_file.path)
            else:
                url = raw_url(source.repo, commit, source_file.path)
            digest, size = download(url, destination, MAX_DOWNLOAD_BYTES)
            require(size > 0, f"{source.key}/{source_file.path}: empty file")
            files[source_file.path] = LockedFile(source_file.role, digest, size)
        unchanged = old is not None and old.files == files and source.kind == "cds"
        sources[source.key] = LockedSource(
            source.title, source.repo, ref, commit, source.license_id, files,
            source.base_url, old.retrieved if unchanged and old else today)
        if old is not None:
            describe_lock_changes(source.key, old, sources[source.key])
    locked_on = today if refreshed_all or previous is None else previous.locked_on
    return Lock(locked_on, sources)


def load_previous_lock(path: Path) -> Lock | None:
    """The existing lock, if usable; a refresh starts from default refs without one."""
    if not path.is_file():
        return None
    try:
        return read_lock(path, allow_missing=True)
    except BuildError as error:
        warn(f"ignoring the existing lock ({error}); using the default refs")
        return None


def describe_lock_changes(key: str, old: LockedSource, new: LockedSource) -> None:
    """Prints what a refresh changed; legal files get a prominent warning."""
    if old.commit != new.commit:
        print(f"{key}: commit {old.commit[:10] or '-'} -> {new.commit[:10] or '-'}", file=sys.stderr)
    for path, locked in new.files.items():
        before = old.files.get(path)
        if before is not None and before.sha256 != locked.sha256:
            if locked.role == "legal":
                warn(f"{key}: LEGAL FILE CHANGED upstream ({path}); review the license terms "
                     "and update ATTRIBUTION.md before shipping")
            else:
                print(f"{key}: {path} changed", file=sys.stderr)


# ==========================================================================================
# Constellations
# ==========================================================================================

@dataclass(frozen=True)
class ConstellationNames:
    """Lookup of IAU abbreviations, case-insensitive, with OpenNGC's Serpens aliases."""

    canonical: Mapping[str, str]

    @classmethod
    def iau(cls) -> ConstellationNames:
        return cls({abbr.lower(): abbr for abbr, _, _ in IAU_CONSTELLATIONS})

    def resolve(self, raw: str, what: str, *, aliases: Mapping[str, str] | None = None) -> str:
        """Returns the canonical abbreviation (e.g. ``UMa``) for ``raw`` or fails."""
        key = raw.strip().lower()
        abbr = (aliases or {}).get(key) or self.canonical.get(key)
        return present(abbr, f"{what}: unknown constellation abbreviation {raw!r}")


def _geo_point(raw: object, what: str) -> tuple[float, float]:
    """Validates a GeoJSON position. d3-celestial stores right ascension as longitude."""
    require(isinstance(raw, list) and len(raw) == 2
            and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in raw),
            f"{what}: malformed coordinate {raw!r}")
    longitude, latitude = float(raw[0]), float(raw[1])
    require(math.isfinite(longitude) and math.isfinite(latitude), f"{what}: non-finite coordinate")
    require_range(longitude, -180.0, 360.0, f"{what} longitude")
    require_range(latitude, -90.0, 90.0, f"{what} latitude")
    return longitude, latitude


def load_json(path: Path) -> object:
    """Loads a JSON file with ``json.load`` (no evaluation of any kind)."""
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError, RecursionError) as error:
        raise BuildError(f"cannot read {path}: {error}") from error


def _features(document: object, what: str) -> list[Item]:
    require(isinstance(document, dict) and isinstance(document.get("features"), list),
            f"{what}: not a GeoJSON FeatureCollection")
    features = document["features"]
    require(all(isinstance(feature, dict) for feature in features), f"{what}: malformed feature")
    return features


def build_constellations(names_path: Path, lines_path: Path, report: Report) -> list[Item]:
    """Merges d3-celestial's names, label positions and stick figures into 88 entries."""
    iau = {abbr: (name, genitive) for abbr, name, genitive in IAU_CONSTELLATIONS}
    require(len(iau) == 88, "internal error: the IAU table must have 88 entries")

    labels: dict[str, tuple[float, float]] = {}
    for feature in _features(load_json(names_path), "constellations.json"):
        abbr, properties = feature.get("id"), feature.get("properties")
        require(isinstance(abbr, str) and abbr in iau and isinstance(properties, dict),
                f"constellations.json: unexpected constellation {abbr!r}")
        name = unicodedata.normalize("NFC", str(properties.get("name")))
        genitive = unicodedata.normalize("NFC", str(properties.get("gen")))
        expected_name, expected_genitive = iau[abbr]
        if abbr in SPLIT_CONSTELLATIONS:
            require(name in SPLIT_CONSTELLATIONS[abbr], f"{abbr}: unexpected part {name!r}")
            expected_name = name
        deviations = {key: value for key, value, expected in
                      (("name", name, expected_name), ("gen", genitive, expected_genitive))
                      if value != expected}
        if deviations:
            require(deviations == KNOWN_D3_DEVIATIONS.get(abbr),
                    f"{abbr}: d3-celestial differs from the IAU table in an unknown way: "
                    f"{deviations}")
            report.note(f"{abbr}: corrected d3-celestial {deviations} to "
                        f"{expected_name!r}/{expected_genitive!r}")
        geometry = feature.get("geometry")
        require(isinstance(geometry, dict) and geometry.get("type") == "Point",
                f"{abbr}: label is not a Point")
        point = _geo_point(geometry.get("coordinates"), f"{abbr} label")
        if abbr not in SPLIT_CONSTELLATIONS or name == SPLIT_CONSTELLATIONS[abbr][0]:
            require(abbr not in labels, f"{abbr}: label given twice")
            labels[abbr] = point
    require(set(labels) == set(iau), f"constellations.json lacks {sorted(set(iau) - set(labels))}")

    lines: dict[str, list[list[list[float]]]] = {abbr: [] for abbr in iau}
    for feature in _features(load_json(lines_path), "constellations.lines.json"):
        abbr, geometry = feature.get("id"), feature.get("geometry")
        require(isinstance(abbr, str) and abbr in iau, f"lines: unexpected id {abbr!r}")
        require(isinstance(geometry, dict) and geometry.get("type") == "MultiLineString"
                and isinstance(geometry.get("coordinates"), list),
                f"{abbr}: lines are not a MultiLineString")
        for raw_line in geometry["coordinates"]:
            require(isinstance(raw_line, list) and len(raw_line) >= 2,
                    f"{abbr}: a stick-figure line needs at least two points")
            points = [_geo_point(raw, f"{abbr} line") for raw in raw_line]
            lines[abbr].append([[rounded(wrap_degrees(lon), 6), rounded(lat, 6)]
                                for lon, lat in points])

    entries = []
    for abbr, name, genitive in sorted(IAU_CONSTELLATIONS, key=lambda item: item[1]):
        require(lines[abbr], f"{abbr}: no stick-figure lines")
        longitude, latitude = labels[abbr]
        entries.append({
            "abbr": abbr,
            "name": name,
            "genitive": genitive,
            "label": [rounded(wrap_degrees(longitude), 6), rounded(latitude, 6)],
            "lines": lines[abbr],
        })
    return entries


# ==========================================================================================
# Stars (HYG Database)
# ==========================================================================================

HYG_COLUMNS = ("id", "hip", "hd", "hr", "proper", "ra", "dec", "dist", "pmra", "pmdec", "mag",
               "spect", "ci", "bayer", "flam", "con")


def read_csv(path: Path, delimiter: str, required: Iterable[str]) -> Iterator[dict[str, str]]:
    """Streams the rows of a UTF-8 CSV file, insisting on the required columns and on rows that
    match the header."""
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter=delimiter)
            missing = [name for name in required if name not in (reader.fieldnames or [])]
            require(not missing, f"{path.name}: missing columns {missing}")
            for number, row in enumerate(reader, start=2):
                require(None not in row and None not in row.values(),
                        f"{path.name}:{number}: row does not match the header")
                yield row
    except (OSError, UnicodeError, csv.Error) as error:
        raise BuildError(f"cannot read {path}: {error}") from error


def bayer_label(code: str, what: str) -> str | None:
    """Converts HYG's ``Alp`` / ``Kap-2`` to ``α`` / ``κ²``."""
    text = code.strip()
    if not text:
        return None
    match = present(re.fullmatch(r"([A-Za-z]{1,3})(?:-(\d{1,2}))?", text),
                    f"{what}: unrecognized Bayer designation {code!r}")
    require(match.group(1) in GREEK_LETTERS, f"{what}: unknown Greek letter {code!r}")
    return GREEK_LETTERS[match.group(1)] + (match.group(2) or "").translate(SUPERSCRIPT_DIGITS)


def hipparcos_epoch_correction(pm_ra: float, declination: float, what: str) -> float:
    """Degrees to add to the HYG right ascension of a Hipparcos star to get its J2000.0 position.

    HYG advanced Hipparcos' epoch-1991.25 positions to 2000.0 by adding ``pm_ra`` times the
    elapsed years to the right ascension, as if the proper motion in right ascension
    (mu_alpha* = mu_alpha cos(dec), in mas/yr) were a rate of change of the coordinate. That
    rate is ``pm_ra / cos(dec)``, so the right ascension is short by the difference. The error
    is negligible for most stars but reaches 18 arcseconds on the sky for Proxima Centauri;
    declinations are unaffected.
    """
    require(abs(declination) < 89.9, f"{what}: too close to a pole to correct the epoch")
    years = J2000_EPOCH - HIPPARCOS_EPOCH
    return pm_ra * years / 3.6e6 * (1.0 / math.cos(math.radians(declination)) - 1.0)


def build_stars(path: Path, constellations: ConstellationNames, report: Report) -> list[Item]:
    """Selects and converts HYG stars: V <= 6.5 or named, each with a Hipparcos or HR number.

    Unnamed entries with neither number are Gliese companions of stars that are already
    present and are dropped; named ones keep the HYG row id. Hipparcos stars get the epoch
    correction of :func:`hipparcos_epoch_correction`.
    """
    stars: list[Item] = []
    dropped_without_id = 0
    named_without_catalog_id = 0
    for row in read_csv(path, ",", HYG_COLUMNS):
        hyg_id = present(parse_int(row["id"], "HYG id"), "HYG row without id")
        if hyg_id == SUN_HYG_ID:
            continue
        what = f"HYG star {hyg_id}"
        name = clean_text(row["proper"], f"{what} name")
        magnitude = parse_float(row["mag"], f"{what} magnitude")
        if magnitude is None:
            require(not name, f"{what}: named star without a magnitude")
            continue
        require_range(magnitude, -30.0, 30.0, f"{what} magnitude")
        if magnitude > STAR_MAGNITUDE_LIMIT and not name:
            continue

        hip, hr = parse_int(row["hip"], f"{what} HIP"), parse_int(row["hr"], f"{what} HR")
        hd = parse_int(row["hd"], f"{what} HD")
        has_catalog_id = hip is not None or hr is not None
        if not has_catalog_id:
            if not name:
                dropped_without_id += 1  # unnamed Gliese companion of a catalogued star
                continue
            named_without_catalog_id += 1

        right_ascension = present(parse_float(row["ra"], f"{what} RA"), f"{what}: no RA")
        declination = present(parse_float(row["dec"], f"{what} Dec"), f"{what}: no Dec")
        require_range(right_ascension, 0.0, 24.0, f"{what} RA (hours)", upper_open=True)
        require_range(declination, -90.0, 90.0, f"{what} Dec")

        star: Item = {}
        if hip is not None:
            star["hip"] = hip
        if hr is not None:
            star["hr"] = hr
        if hd is not None:
            star["hd"] = hd
        if not has_catalog_id:
            star["hyg"] = hyg_id
        if name:
            star["n"] = name
        bayer = bayer_label(row["bayer"], what)
        if bayer:
            star["b"] = bayer
        flamsteed = parse_int(row["flam"], f"{what} Flamsteed")
        if flamsteed is not None:
            star["f"] = flamsteed
        star["c"] = constellations.resolve(row["con"], what)
        pm_ra = parse_float(row["pmra"], f"{what} pmRA")
        pm_dec = parse_float(row["pmdec"], f"{what} pmDec")
        ra_degrees = right_ascension * 15.0
        if hip is not None and pm_ra is not None:
            ra_degrees += hipparcos_epoch_correction(pm_ra, declination, what)
        star["ra"] = wrap_degrees(rounded(ra_degrees, 6))
        star["de"] = rounded(declination, 6)
        if pm_ra is not None and pm_dec is not None and (pm_ra != 0.0 or pm_dec != 0.0):
            star["pa"], star["pd"] = rounded(pm_ra, 2), rounded(pm_dec, 2)
        star["m"] = rounded(magnitude, 2)
        color = parse_float(row["ci"], f"{what} B-V")
        if color is not None:
            star["ci"] = rounded(color, 2)
        spectral = clean_text(row["spect"], f"{what} spectral type")[:12].rstrip()
        if spectral:
            star["sp"] = spectral
        distance = parse_float(row["dist"], f"{what} distance")
        if distance is not None and 0.0 < distance < 100000.0:  # >= 100000 means "unknown"
            star["d"] = rounded(distance, 2)
        stars.append(star)

    stars.sort(key=lambda s: (s["m"], s.get("hip", math.inf), s.get("hr", math.inf),
                              s.get("hyg", math.inf)))
    report.note(f"stars: {dropped_without_id} unnamed entries with neither HIP nor HR dropped "
                "(Gliese companions within arcseconds of a catalogued star)")
    report.note(f"stars: {named_without_catalog_id} named entries without HIP/HR keep "
                "the HYG row id in 'hyg'")
    return stars


# ==========================================================================================
# Deep-sky objects (OpenNGC, Sharpless, Barnard, Lynds, Dias)
# ==========================================================================================

NGC_COLUMNS = ("Name", "Type", "RA", "Dec", "Const", "MajAx", "MinAx", "PosAng", "B-Mag",
               "V-Mag", "SurfBr", "Hubble", "M", "NGC", "IC", "Identifiers", "Common names")
_OPENNGC_NAME = re.compile(r"(NGC|IC)(\d{4})")
_OPENNGC_REFERENCE = re.compile(r"(\d{1,4})([A-Za-z]{1,2}|\s?NED\d{2})?")
# Cross-identifications that OpenNGC lists in its "Identifiers" column and that the catalog
# keeps as extra designations: Caldwell ("C 020"), Sharpless 2 ("SH 2-155"), Melotte ("Mel 025")
# and Collinder ("Cl 050"). The value is the designation prefix of the catalog.
_IDENTIFIER_PREFIXES = {"C": "C", "SH 2-": "Sh2-", "Mel": "Mel", "Cl": "Cl"}
_IDENTIFIER = re.compile(r"(C|SH 2-|Mel|Cl)\s?(\d{1,3})")


@dataclass(frozen=True)
class NgcRow:
    """The parts of one OpenNGC row the pipeline uses."""

    name: str
    kind: str
    ra: str
    dec: str
    constellation: str
    major_axis: float | None
    minor_axis: float | None
    position_angle: float | None
    b_mag: float | None
    v_mag: float | None
    surface_brightness: float | None
    hubble: str
    messier: int | None
    references: tuple[str, ...]  # OpenNGC row names of the same object, e.g. "NGC0651"
    identifiers: tuple[str, ...]  # other catalogue designations, e.g. "C 020", "LBN 373"
    common_names: tuple[str, ...]


def _references(raw: str, prefix: str, what: str) -> tuple[str, ...]:
    names = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        match = present(_OPENNGC_REFERENCE.fullmatch(token),
                        f"{what}: unrecognized cross-reference {raw!r}")
        suffix = (match.group(2) or "").strip()
        suffix = f" {suffix}" if suffix.startswith("NED") else suffix
        names.append(f"{prefix}{int(match.group(1)):04d}{suffix}")
    return tuple(names)


def _split_common_names(raw: str, what: str) -> tuple[str, ...]:
    names: list[str] = []
    for part in raw.split(","):
        name = clean_text(part, what)
        if name[:4].lower() == "the " and len(name) > 4:
            name = name[4:]
        if name and name.casefold() not in {existing.casefold() for existing in names}:
            names.append(name)
    return tuple(names)


def read_ngc_rows(path: Path) -> list[NgcRow]:
    """Parses an OpenNGC CSV file (``;`` separated)."""
    rows = []
    for record in read_csv(path, ";", NGC_COLUMNS):
        name = clean_text(record["Name"], "OpenNGC name")
        what = f"OpenNGC {name}"
        require(bool(name), f"{path.name}: row without a name")
        messier = parse_int(record["M"], f"{what} M")
        if messier is not None:
            require_range(messier, 1, MESSIER_COUNT, f"{what} Messier number")
        rows.append(NgcRow(
            name=name,
            kind=record["Type"].strip(),
            ra=record["RA"],
            dec=record["Dec"],
            constellation=record["Const"],
            major_axis=parse_float(record["MajAx"], f"{what} MajAx"),
            minor_axis=parse_float(record["MinAx"], f"{what} MinAx"),
            position_angle=parse_float(record["PosAng"], f"{what} PosAng"),
            b_mag=parse_float(record["B-Mag"], f"{what} B-Mag"),
            v_mag=parse_float(record["V-Mag"], f"{what} V-Mag"),
            surface_brightness=parse_float(record["SurfBr"], f"{what} SurfBr"),
            hubble=clean_text(record["Hubble"], f"{what} Hubble"),
            messier=messier,
            references=_references(record["NGC"], "NGC", what)
                       + _references(record["IC"], "IC", what),
            identifiers=tuple(token for token in
                              (clean_text(part, f"{what} identifiers")
                               for part in record["Identifiers"].split(",")) if token),
            common_names=_split_common_names(record["Common names"], f"{what} common names"),
        ))
    return rows


def _primary(rows: Mapping[str, NgcRow], name: str) -> NgcRow | None:
    """Follows ``Dup`` rows to the object they duplicate; ``None`` if it does not exist."""
    seen: set[str] = set()
    row = rows.get(name)
    while row is not None and row.kind == "Dup":
        require(row.name not in seen, f"OpenNGC duplicate cycle at {row.name}")
        seen.add(row.name)
        row = rows.get(row.references[0]) if row.references else None
    return row if row is not None and row.kind not in ("Dup", "NonEx") else None


def _designations(rows: Mapping[str, NgcRow]) -> dict[str, dict[str, list[int]]]:
    """The NGC and IC numbers of every primary row, keyed by row name.

    A row's own number comes first, then its cross-references and the numbers of ``Dup`` rows
    that duplicate it, ascending. So "NGC 2244", a duplicate of NGC 2239, is found on NGC 2239.
    Sub-component designations such as "NGC 4567A" cannot be represented as integers and are
    left out.
    """
    found: dict[str, dict[str, list[int]]] = {}

    def add(target: str, designation: str) -> None:
        match = _OPENNGC_NAME.fullmatch(designation)
        if match:
            numbers = found.setdefault(target, {"NGC": [], "IC": []})[match.group(1)]
            if int(match.group(2)) not in numbers:
                numbers.append(int(match.group(2)))

    for row in rows.values():
        if row.kind not in ("Dup", "NonEx"):
            add(row.name, row.name)
            for reference in row.references:
                add(row.name, reference)
    for row in rows.values():
        if row.kind == "Dup":
            for reference in row.references:
                primary = _primary(rows, reference)
                if primary is not None:
                    add(primary.name, row.name)
    for target, by_catalogue in found.items():
        for prefix, numbers in by_catalogue.items():
            own = [int(m.group(2)) for m in [_OPENNGC_NAME.fullmatch(target)]
                   if m and m.group(1) == prefix]
            numbers[:] = own + sorted(set(numbers) - set(own))
    return found


def _object_id(row: NgcRow, messier: int | None) -> str:
    if messier is not None:
        return f"M{messier}"
    return re.sub(r"^([A-Za-z]+)0*(\d)", r"\1\2", row.name).replace(" ", "_")


def _qualifies(row: NgcRow, has_names: bool) -> bool:
    """The first (legacy) selection rule: magnitude, size and names."""
    if has_names:
        return True
    if row.kind in PLAIN_STAR_TYPES:
        return False
    if row.v_mag is not None:
        return row.v_mag <= DSO_VISUAL_MAGNITUDE_LIMIT
    if row.b_mag is not None:
        return row.b_mag <= DSO_BLUE_MAGNITUDE_LIMIT
    return row.kind in NEBULA_TYPES and (row.major_axis or 0.0) >= NEBULA_MIN_SIZE_ARCMIN


def _extended_qualifies(row: NgcRow) -> bool:
    """The extended selection rule: what a camera lens or a small telescope can reach."""
    if row.kind in PLAIN_STAR_TYPES:
        return False
    size = row.major_axis or 0.0
    if row.v_mag is not None and row.v_mag <= EXT_VISUAL_MAGNITUDE_LIMIT:
        return True
    if row.v_mag is None and row.b_mag is not None and row.b_mag <= EXT_BLUE_MAGNITUDE_LIMIT:
        return True
    if row.kind in NEBULA_TYPES and size >= EXT_NEBULA_MIN_SIZE_ARCMIN:
        return True
    return row.kind in CLUSTER_TYPES and size >= EXT_CLUSTER_MIN_SIZE_ARCMIN


def _ordered_names(row: NgcRow) -> tuple[str, ...]:
    """The object's names in display order: supplementary, then OpenNGC's; acronyms last."""
    removed = {name.casefold() for name in REMOVED_NAMES.get(row.name, ())}
    extra = SUPPLEMENTARY_NAMES.get(row.name)
    names: list[str] = []
    for name in (extra[1] if extra else ()) + row.common_names:
        if name.casefold() not in removed and name.casefold() not in {n.casefold() for n in names}:
            names.append(name)
    names.sort(key=lambda name: re.fullmatch(r"[A-Z]{2,4}", name) is not None)
    return tuple(names)


# ------------------------------------------------------------------------------------------
# Hand-made tables for the catalogues that come from CDS
# ------------------------------------------------------------------------------------------
# Every entry names the constellation the object is expected in, which is checked against the
# computed one, so a mistyped number fails the build instead of attaching a name to the wrong
# object. The identifications were made by comparing positions and sizes with OpenNGC and
# reviewed by hand; each must lie within half a diameter of the Sharpless center.

# Sharpless 2 regions that are an object OpenNGC already lists: Sh2 number -> OpenNGC row. The
# region becomes one more designation of that object instead of a second marker on the sky.
SHARPLESS_IDENTIFICATIONS: dict[int, str] = {
    8: "NGC6334", 11: "NGC6357", 25: "NGC6523", 30: "NGC6514", 37: "IC1284", 44: "IC4701",
    45: "NGC6618", 49: "NGC6611", 86: "NGC6823", 95: "NGC6842", 100: "NGC6857", 103: "NGC6960",
    105: "NGC6888", 117: "NGC7000", 125: "IC5146", 131: "IC1396", 142: "NGC7380",
    155: "C009", 156: "IC1470", 158: "NGC7538", 162: "NGC7635", 171: "NGC7822", 184: "NGC0281",
    185: "IC0063", 190: "IC1805", 199: "IC1848", 206: "NGC1491", 212: "NGC1624",
    220: "NGC1499", 222: "NGC1579", 229: "IC0405", 234: "IC0417", 236: "IC0410",
    237: "NGC1931", 238: "NGC1555", 244: "NGC1952", 248: "IC0443", 252: "NGC2174",
    255: "IC2162", 273: "NGC2264",
    275: "NGC2238", 277: "NGC2024", 279: "NGC1977", 281: "NGC1976", 296: "IC2177",
    298: "NGC2359", 311: "NGC2467",
}

# Popular names of Sharpless regions that OpenNGC does not list: Sh2 number -> (constellation, names).
SHARPLESS_NAMES: dict[int, tuple[str, tuple[str, ...]]] = {
    101: ("Cyg", ("Tulip Nebula",)),
    108: ("Cyg", ("Gamma Cygni Nebula",)),
    129: ("Cep", ("Flying Bat Nebula",)),
    132: ("Cep", ("Lion Nebula",)),
    136: ("Cep", ("Ghost Nebula",)),
    157: ("Cas", ("Lobster Claw Nebula",)),
    240: ("Tau", ("Spaghetti Nebula", "Simeis 147")),
    261: ("Ori", ("Lower's Nebula",)),
    264: ("Ori", ("Lambda Orionis Ring",)),
    274: ("Gem", ("Medusa Nebula", "Abell 21")),
    276: ("Ori", ("Barnard's Loop",)),
    290: ("Cnc", ("Abell 31",)),
    308: ("CMa", ("Dolphin Head Nebula",)),
}

# Sharpless regions that are not HII regions (the catalogue lists every one of them as HII): the
# well-known planetary nebulae and the supernova remnant Simeis 147. Sh2 number -> OpenNGC type.
SHARPLESS_TYPES: dict[int, str] = {188: "PN", 216: "PN", 240: "SNR", 274: "PN", 290: "PN"}

# Popular names of Barnard objects (the number may carry a letter) and of Lynds clouds.
BARNARD_NAMES: dict[str, tuple[str, str]] = {
    "72": ("Oph", "Snake Nebula"),
    "78": ("Oph", "Pipe Nebula"),
    "86": ("Sgr", "Ink Spot Nebula"),
    "150": ("Cep", "Seahorse Nebula"),
}
LYNDS_NAMES: dict[int, tuple[str, str]] = {
    1235: ("Cep", "Shark Nebula"),
    1622: ("Ori", "Boogeyman Nebula"),
}

# Open clusters of the Dias catalogue that are another object in the catalog: designation ->
# OpenNGC row. Clusters whose designation the catalog carries already (Melotte 22 is the
# Pleiades, Melotte 25 the Hyades, Melotte 111 is listed) are recognized by themselves.
OPEN_CLUSTER_IDENTIFICATIONS: dict[str, str] = {"Trumpler 37": "IC1396"}

# Popular names of the Dias clusters.
OPEN_CLUSTER_NAMES: dict[str, tuple[str, str]] = {
    "Melotte 20": ("Per", "Alpha Persei Cluster"),
    "Collinder 69": ("Ori", "Lambda Orionis Cluster"),
    "Collinder 70": ("Ori", "Orion's Belt Cluster"),
    "Stock 2": ("Cas", "Muscleman Cluster"),
}

# Objects the catalog treats as showpieces beyond the Messier and Caldwell objects: widely
# photographed targets with a popular name. Prominence 1.
SHOWPIECES: tuple[str, ...] = (
    "B33", "NGC2024", "IC1805", "IC1848", "NGC281", "NGC1499", "NGC7380", "IC1396", "IC5070",
    "NGC6334", "NGC6357", "NGC2359", "IC2177", "NGC1977", "IC4592", "NGC1909", "NGC1333",
    "IC4604", "IC4628", "NGC2174", "NGC7822", "Sh2-129", "Sh2-132", "Sh2-240", "Sh2-276",
    "LDN1622",
)


# ------------------------------------------------------------------------------------------
# Positions: precession and constellations
# ------------------------------------------------------------------------------------------

def precess(ra: float, dec: float, from_jd: float, to_jd: float) -> tuple[float, float]:
    """Precesses a position (degrees) between two equinoxes (IAU 1976, Meeus ch. 21).

    The Sharpless and Lynds positions are referred to the equinoxes B1900.0 and B1950.0. Their own
    accuracy is a few arcminutes, so the plain rotation is enough; no proper motion is applied.
    """
    t0 = (from_jd - JD_J2000) / 36525.0
    t = (to_jd - from_jd) / 36525.0
    base = (2306.2181 + 1.39656 * t0 - 0.000139 * t0 * t0) * t
    zeta = (base + (0.30188 - 0.000344 * t0) * t * t + 0.017998 * t ** 3) / 3600.0
    z = (base + (1.09468 + 0.000066 * t0) * t * t + 0.018203 * t ** 3) / 3600.0
    theta = ((2004.3109 - 0.85330 * t0 - 0.000217 * t0 * t0) * t
             - (0.42665 + 0.000217 * t0) * t * t - 0.041833 * t ** 3) / 3600.0
    radians = math.radians
    a = math.cos(radians(dec)) * math.sin(radians(ra + zeta))
    b = (math.cos(radians(theta)) * math.cos(radians(dec)) * math.cos(radians(ra + zeta))
         - math.sin(radians(theta)) * math.sin(radians(dec)))
    c = (math.sin(radians(theta)) * math.cos(radians(dec)) * math.cos(radians(ra + zeta))
         + math.cos(radians(theta)) * math.sin(radians(dec)))
    return (wrap_degrees(math.degrees(math.atan2(a, b)) + z),
            math.degrees(math.asin(max(-1.0, min(1.0, c)))))


def angular_separation(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Angular distance in degrees between two (right ascension, declination) positions."""
    ra1, de1, ra2, de2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    sine = math.hypot(math.cos(de2) * math.sin(ra2 - ra1),
                      math.cos(de1) * math.sin(de2) - math.sin(de1) * math.cos(de2) * math.cos(ra2 - ra1))
    cosine = math.sin(de1) * math.sin(de2) + math.cos(de1) * math.cos(de2) * math.cos(ra2 - ra1)
    return math.degrees(math.atan2(sine, cosine))


@dataclass(frozen=True)
class ConstellationBoundaries:
    """The IAU constellation boundaries of Delporte (1930) as arranged by Roman (1987).

    Each row is the southern edge of a constellation's part: the right ascension range in hours
    and the lower declination, all at the equinox B1875.0. The first row, in file order, that
    contains a position is its constellation.
    """

    rows: tuple[tuple[float, float, float, str], ...]

    @classmethod
    def read(cls, path: Path, constellations: ConstellationNames) -> ConstellationBoundaries:
        rows = []
        try:
            lines = path.read_text(encoding="ascii").splitlines()
        except (OSError, UnicodeError) as error:
            raise BuildError(f"cannot read {path}: {error}") from error
        for number, line in enumerate(lines, start=1):
            what = f"{path.name}:{number}"
            if not line.strip():
                continue
            low = present(parse_float(line[1:8], f"{what} RA low"), f"{what}: no lower RA")
            high = present(parse_float(line[9:16], f"{what} RA high"), f"{what}: no upper RA")
            south = present(parse_float(line[17:25], f"{what} Dec"), f"{what}: no declination")
            require(0.0 <= low < high <= 24.0 and -90.0 <= south <= 90.0, f"{what}: bad row")
            rows.append((low, high, south, constellations.resolve(line[26:29], what)))
        require(len(rows) == 357, f"{path.name}: expected 357 boundary rows, found {len(rows)}")
        require({row[3] for row in rows} == set(constellations.canonical.values()),
                f"{path.name}: does not cover exactly the 88 constellations")
        return cls(tuple(rows))

    def find(self, ra: float, dec: float, what: str) -> str:
        """The IAU abbreviation of the constellation that contains a J2000.0 position."""
        ra_1875, dec_1875 = precess(ra, dec, JD_J2000, JD_B1875)
        hours = ra_1875 / 15.0
        for low, high, south, abbreviation in self.rows:
            if south <= dec_1875 and low <= hours < high:
                return abbreviation
        raise BuildError(f"{what}: no constellation contains ({ra}, {dec})")


# ------------------------------------------------------------------------------------------
# CDS catalogues
# ------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class SharplessRegion:
    """One row of Sharpless' catalogue of HII regions, with the J2000.0 position."""

    number: int
    ra: float
    dec: float
    diameter: float  # arcminutes, the largest extent
    form: int  # 1 circular, 2 elliptical, 3 irregular
    brightness: int  # 1 faintest ... 3 brightest


def _fixed_int(text: str, what: str) -> int:
    """An integer field of a fixed-width record; a blank field is 0 (as in the CDS files)."""
    value = text.strip()
    if not value:
        return 0
    require(re.fullmatch(r"\d{1,9}", value) is not None, f"{what}: not an integer: {text!r}")
    return int(value)


def _signed_degrees(sign: str, degrees: str, minutes: str, seconds: str, what: str) -> float:
    require(sign in "+- ", f"{what}: bad sign {sign!r}")
    value = (_fixed_int(degrees, what) + _fixed_int(minutes, what) / 60.0
             + _fixed_int(seconds, what) / 3600.0)
    return -value if sign == "-" else value


def _read_text_lines(path: Path) -> list[str]:
    """The lines of a plain or gzip-compressed ASCII file."""
    opener = gzip.open if path.suffix == ".gz" else open
    try:
        with opener(path, "rt", encoding="ascii", newline="") as handle:
            return handle.read().splitlines()
    except (OSError, UnicodeError, EOFError) as error:
        raise BuildError(f"cannot read {path}: {error}") from error


def read_sharpless(path: Path) -> list[SharplessRegion]:
    """Parses VII/20 ``catalog.dat``. Positions are at B1900.0 and are precessed to J2000.0."""
    regions = []
    for number, line in enumerate(_read_text_lines(path), start=1):
        what = f"Sharpless line {number}"
        require(len(line) >= 57, f"{what}: short record")
        sh2 = _fixed_int(line[0:4], what)
        hours = (_fixed_int(line[20:22], what) * 3600.0 + _fixed_int(line[22:24], what) * 60.0
                 + _fixed_int(line[24:27], what) / 10.0) / 3600.0
        dec = _signed_degrees(line[27], line[28:30], line[30:32], line[32:34], what)
        ra, de = precess(hours * 15.0, dec, JD_B1900, JD_J2000)
        diameter, form, brightness = (_fixed_int(line[48:52], what), _fixed_int(line[52:53], what),
                                      _fixed_int(line[54:55], what))
        require(1 <= sh2 <= 313 and diameter > 0 and form in (1, 2, 3) and brightness in (1, 2, 3)
                and 0.0 <= hours < 24.0 and -90.0 <= dec <= 90.0, f"{what}: values out of range")
        regions.append(SharplessRegion(sh2, ra, de, float(diameter), form, brightness))
    require([r.number for r in regions] == list(range(1, 314)),
            "Sharpless: expected the regions 1 to 313 in order")
    return regions


@dataclass(frozen=True)
class BarnardObject:
    """One of Barnard's dark objects, with the J2000.0 position of the CDS file."""

    designation: str  # "33", "67a"
    ra: float
    dec: float
    b1875: tuple[float, float]  # the original position, to cross-check the J2000.0 one
    diameter: float | None  # arcminutes


def read_barnard(path: Path) -> list[BarnardObject]:
    """Parses VII/220A ``barnard.dat``."""
    objects = []
    for number, line in enumerate(_read_text_lines(path), start=1):
        what = f"Barnard line {number}"
        line = line.ljust(44)
        designation = line[1:5].strip().lower()
        require(re.fullmatch(r"\d{1,3}[a-z]?", designation) is not None,
                f"{what}: bad Barnard number {line[1:5]!r}")
        ra_1875 = (_fixed_int(line[5:7], what) + _fixed_int(line[8:10], what) / 60.0
                   + _fixed_int(line[11:13], what) / 3600.0) * 15.0
        de_1875 = _signed_degrees(line[14], line[15:17], line[18:20], "0", what)
        ra = (_fixed_int(line[22:24], what) + _fixed_int(line[25:27], what) / 60.0
              + _fixed_int(line[28:30], what) / 3600.0) * 15.0
        dec = _signed_degrees(line[32], line[33:35], line[36:38], "0", what)
        size = parse_float(line[39:44], f"{what} diameter")
        require(0.0 <= ra < 360.0 and -90.0 <= dec <= 90.0 and (size is None or 0.0 < size <= 600.0),
                f"{what}: values out of range")
        objects.append(BarnardObject(designation, ra, dec, (ra_1875, de_1875), size))
    require(len(objects) == 349, f"Barnard: expected 349 objects, found {len(objects)}")
    require(len({o.designation for o in objects}) == 349, "Barnard: designations repeat")
    return objects


@dataclass(frozen=True)
class LyndsCloud:
    """One Lynds dark cloud, with the J2000.0 position and its area-equivalent diameter."""

    number: int
    ra: float
    dec: float
    area: float  # square degrees
    opacity: int  # 1 lightest ... 6 darkest
    barnard: tuple[str, ...]  # Barnard objects the cloud contains, as in the source

    @property
    def diameter(self) -> float:
        """Diameter in arcminutes of the circle that has the cloud's area."""
        return 2.0 * math.sqrt(self.area / math.pi) * 60.0


def read_lynds(path: Path) -> list[LyndsCloud]:
    """Parses VII/7A ``ldn``. Positions are at B1950.0 and are precessed to J2000.0.

    The four clouds at the end of the file that have no LDN number are skipped.
    """
    clouds = []
    for number, line in enumerate(_read_text_lines(path), start=1):
        what = f"Lynds line {number}"
        line = line.ljust(92)
        if not line[0:4].strip():
            continue
        ldn = _fixed_int(line[0:4], what)
        hours = _fixed_int(line[5:7], what) + (parse_float(line[8:12], f"{what} RA") or 0.0) / 60.0
        dec = _signed_degrees(line[15], line[16:18], line[19:21], "0", what)
        area = present(parse_float(line[36:43], f"{what} area"), f"{what}: no area")
        opacity = _fixed_int(line[44:45], what)
        ra, de = precess(hours * 15.0, dec, JD_B1950, JD_J2000)
        require(1 <= ldn <= 1802 and 0.0 <= hours < 24.0 and -90.0 <= dec <= 90.0
                and 0.0 <= area < 100.0 and 0 <= opacity <= 6, f"{what}: values out of range")
        barnard = tuple(token.lower() for token in
                        (line[60 + 4 * k:64 + 4 * k].strip() for k in range(8)) if token)
        clouds.append(LyndsCloud(ldn, ra, de, area, opacity, barnard))
    require(len(clouds) == 1787, f"Lynds: expected 1,787 numbered clouds, found {len(clouds)}")
    require(len({c.number for c in clouds}) == len(clouds), "Lynds: numbers repeat")
    return clouds


@dataclass(frozen=True)
class OpenClusterRecord:
    """A Collinder, Melotte, Trumpler or Stock cluster of the Dias catalogue (J2000.0)."""

    catalogue: str
    number: int
    ra: float
    dec: float
    diameter: float  # arcminutes

    @property
    def designation(self) -> str:
        return f"{self.catalogue} {self.number}"

    @property
    def object_id(self) -> str:
        return f"{OPEN_CLUSTER_CATALOGUES[self.catalogue]}{self.number}"


def read_dias(path: Path) -> list[OpenClusterRecord]:
    """Parses B/ocl ``clusters.dat``; returns the clusters of :data:`OPEN_CLUSTER_CATALOGUES`."""
    clusters = []
    for number, line in enumerate(_read_text_lines(path), start=1):
        what = f"Dias line {number}"
        require(len(line) >= 36, f"{what}: short record")
        line = line.ljust(47)
        match = re.fullmatch(r"([A-Za-z]+) (\d+)", line[0:17].strip())
        if match is None or match.group(1) not in OPEN_CLUSTER_CATALOGUES:
            continue
        ra = (_fixed_int(line[18:20], what) + _fixed_int(line[21:23], what) / 60.0
              + _fixed_int(line[24:26], what) / 3600.0) * 15.0
        dec = _signed_degrees(line[27], line[28:30], line[31:33], line[34:36], what)
        size = parse_float(line[41:47], f"{what} diameter")
        require(0.0 <= ra < 360.0 and -90.0 <= dec <= 90.0, f"{what}: position out of range")
        if size is not None and size > 0.0:
            clusters.append(OpenClusterRecord(match.group(1), int(match.group(2)), ra, dec, size))
    return clusters


# ------------------------------------------------------------------------------------------
# Building the catalog
# ------------------------------------------------------------------------------------------

@dataclass
class DsoDraft:
    """A catalog object while it is assembled; :func:`draft_item` turns it into JSON."""

    id: str
    kind: str
    ra: float
    de: float
    origin: str  # openngc, sharpless, barnard, lynds or dias
    messier: int | None = None
    ngc: list[int] = field(default_factory=list)
    ic: list[int] = field(default_factory=list)
    cat: list[str] = field(default_factory=list)
    names: list[str] = field(default_factory=list)
    constellation: str | None = None
    v_mag: float | None = None
    b_mag: float | None = None
    major: float | None = None
    minor: float | None = None
    position_angle: float | None = None
    hubble: str = ""
    surface_brightness: float | None = None
    legacy: bool = False  # selected by the first (pre-Caldwell) rule
    caldwell: int | None = None
    sharpless_size: float | None = None  # of the Sharpless 2 region this object is or contains
    sharpless_brightness: int | None = None
    opacity: int | None = None

    @property
    def magnitude(self) -> float | None:
        """The magnitude the apps show: V, else B."""
        return self.v_mag if self.v_mag is not None else self.b_mag

    def designations(self) -> list[str]:
        """Every catalogue designation in compact form: ``M31``, ``NGC224``, ``C14``, ``Sh2-155``."""
        found = [self.id] if re.fullmatch(r"(?:M|NGC|IC)\d+", self.id) is None else []
        if self.messier is not None:
            found.append(f"M{self.messier}")
        found += [f"NGC{n}" for n in self.ngc] + [f"IC{n}" for n in self.ic]
        return found + self.cat


def _row_cross_identifications(row: NgcRow) -> list[str]:
    """Caldwell, Sharpless 2, Melotte and Collinder designations from the Identifiers column."""
    found = []
    for token in row.identifiers:
        match = _IDENTIFIER.fullmatch(token)
        if match:
            found.append(f"{_IDENTIFIER_PREFIXES[match.group(1)]}{int(match.group(2))}")
    return found


def _cat_sort_key(designation: str) -> tuple[int, int]:
    """Caldwell first, then Sharpless, Melotte and Collinder numbers; ascending within each."""
    order = {"C": 0, "Sh2-": 1, "Mel": 2, "Cl": 3, "Tr": 4, "St": 5, "B": 6, "LDN": 7}
    prefix = re.match(r"[A-Za-z]+(?:2-)?", designation).group(0)  # type: ignore[union-attr]
    return order.get(prefix, 9), int(re.search(r"\d+", designation[len(prefix):]).group(0))  # type: ignore[union-attr]


def openngc_drafts(rows: Mapping[str, NgcRow], messier: Mapping[str, int],
                   designations: Mapping[str, dict[str, list[int]]], forced: set[str],
                   constellations: ConstellationNames) -> dict[str, DsoDraft]:
    """The OpenNGC objects of the first and the extended selection, keyed by row name.

    Beyond the selection rules, every Caldwell object and every row in ``forced`` (those the
    hand-made tables refer to) is taken.
    """
    drafts: dict[str, DsoDraft] = {}
    caldwell_rows: dict[int, str] = {}
    for row in rows.values():
        if row.kind in EXCLUDED_DSO_TYPES:
            continue
        for designation in _row_cross_identifications(row):
            if designation.startswith("C") and designation[1].isdigit():
                number = int(designation[1:])
                require(number not in caldwell_rows,
                        f"Caldwell {number} is on {caldwell_rows.get(number)} and {row.name}")
                caldwell_rows[number] = row.name
        own = re.fullmatch(r"C(\d{3})", row.name)  # the four Caldwell objects OpenNGC lists as C###
        if own:
            caldwell_rows[int(own.group(1))] = row.name

    caldwell_of = {name: number for number, name in caldwell_rows.items()}
    for row in rows.values():
        if row.kind in EXCLUDED_DSO_TYPES:
            continue
        number = messier.get(row.name)
        names = _ordered_names(row)
        legacy = number is not None or _qualifies(row, bool(names))
        if not (legacy or row.name in caldwell_of or row.name in forced or _extended_qualifies(row)):
            continue
        what = f"OpenNGC {row.name}"
        require(row.kind in DSO_TYPES, f"{what}: unexpected type {row.kind!r}")
        draft = DsoDraft(
            id=_object_id(row, number), kind=row.kind,
            ra=wrap_degrees(rounded(right_ascension_degrees(row.ra, f"{what} RA"), 6)),
            de=rounded(declination_degrees(row.dec, f"{what} Dec"), 6),
            origin="openngc", messier=number, names=list(names), legacy=legacy,
            caldwell=caldwell_of.get(row.name), v_mag=row.v_mag, b_mag=row.b_mag,
            major=row.major_axis, minor=row.minor_axis, position_angle=row.position_angle,
            hubble=row.hubble, surface_brightness=row.surface_brightness)
        by_catalogue = designations.get(row.name, {})
        draft.ngc = list(by_catalogue.get("NGC", []))
        draft.ic = list(by_catalogue.get("IC", []))
        if row.constellation.strip():
            draft.constellation = constellations.resolve(
                row.constellation, what, aliases=OPENNGC_CONSTELLATION_ALIASES)
        cat = [c for c in _row_cross_identifications(row) if not c.startswith("C") or not c[1:].isdigit()]
        if draft.caldwell is not None and not re.fullmatch(r"C\d+", draft.id):
            cat.append(f"C{draft.caldwell}")
        own_id = _object_id(row, None)
        if number is not None and own_id != f"M{number}" and not _OPENNGC_NAME.fullmatch(row.name):
            cat.append(own_id)  # M45 is also Melotte 22
        draft.cat = sorted(dict.fromkeys(cat), key=_cat_sort_key)
        drafts[row.name] = draft
    return drafts


def drop_foreign_numbers(drafts: Mapping[str, DsoDraft], report: Report) -> None:
    """Removes NGC/IC cross-references that point at another object of the catalog.

    An NGC or IC number belongs to the object that bears it as its name. OpenNGC lists a few
    cross-references to numbers that are galaxies in their own right (NGC 7418 and NGC 7368 both
    "are" IC 1459, which is another galaxy 35 arcminutes away); the first release never met
    them because it listed neither of the two.
    """
    owners = {draft.id: draft for draft in drafts.values()}
    for draft in drafts.values():
        for numbers, prefix in ((draft.ngc, "NGC"), (draft.ic, "IC")):
            for number in list(numbers):
                owner = owners.get(f"{prefix}{number}")
                if owner is not None and owner is not draft:
                    numbers.remove(number)
                    report.note(f"dsos: {draft.id} does not carry {prefix} {number}: it is "
                                f"a listed object of its own")


def sharpless_drafts(regions: Sequence[SharplessRegion], drafts: dict[str, DsoDraft],
                     boundaries: ConstellationBoundaries, report: Report) -> list[DsoDraft]:
    """Adds the Sharpless 2 regions: as designations of OpenNGC objects or as new objects."""
    by_number = {r.number: r for r in regions}
    identified: dict[int, str] = dict(SHARPLESS_IDENTIFICATIONS)
    for name, draft in drafts.items():
        for designation in draft.cat:
            if designation.startswith("Sh2-"):
                number = int(designation[4:])
                require(identified.get(number, name) == name,
                        f"Sh2-{number} is {identified.get(number)} in the table but {name} in OpenNGC")
                identified[number] = name
    merged = 0
    for number, row_name in sorted(identified.items()):
        region = present(by_number.get(number), f"Sh2-{number}: not in the catalogue")
        target = present(drafts.get(row_name), f"Sh2-{number}: {row_name} is not in the catalog")
        separation = angular_separation((region.ra, region.dec), (target.ra, target.de))
        require(separation <= max(0.25, region.diameter / 120.0),
                f"Sh2-{number} is {separation:.2f} degrees from {row_name}")
        designation = f"Sh2-{number}"
        if designation not in target.cat:
            target.cat.append(designation)
            target.cat.sort(key=_cat_sort_key)
        target.sharpless_size = float(region.diameter)
        target.sharpless_brightness = region.brightness
        merged += 1
    created = []
    for region in regions:
        if region.number in identified:
            continue
        what = f"Sh2-{region.number}"
        constellation = boundaries.find(region.ra, region.dec, what)
        name = SHARPLESS_NAMES.get(region.number)
        if name is not None:
            require(name[0] == constellation,
                    f"{what} ({name[1][0]}) lies in {constellation}, not {name[0]}")
        draft = DsoDraft(
            id=what, kind=SHARPLESS_TYPES.get(region.number, "HII"), origin="sharpless",
            ra=rounded(region.ra, 6), de=rounded(region.dec, 6), constellation=constellation,
            names=list(name[1]) if name else [], major=float(region.diameter),
            minor=float(region.diameter) if region.form == 1 else None,
            sharpless_size=float(region.diameter), sharpless_brightness=region.brightness)
        created.append(draft)
    for number, (constellation, names) in SHARPLESS_NAMES.items():
        require(number not in identified, f"Sh2-{number} ({names[0]}) is an OpenNGC object already")
    report.note(f"dsos: Sharpless 2: {merged} regions are designations of OpenNGC objects, "
                f"{len(created)} are new objects")
    return created


def barnard_drafts(objects: Sequence[BarnardObject], existing: Mapping[str, DsoDraft],
                   boundaries: ConstellationBoundaries, report: Report) -> list[DsoDraft]:
    """Adds Barnard's dark objects that OpenNGC does not list (it has B 33, the Horsehead)."""
    by_id = {draft.id: draft for draft in existing.values()}
    created, skipped = [], 0
    for item in objects:
        identifier = f"B{item.designation}"
        what = f"Barnard {item.designation}"
        # The CDS positions come from precessing Barnard's 1875 ones; check the two agree.
        precessed = precess(item.b1875[0], item.b1875[1], JD_B1875, JD_J2000)
        require(angular_separation(precessed, (item.ra, item.dec)) < 0.3,
                f"{what}: the J2000 position is far from the precessed 1875 position")
        if identifier in by_id:
            require(angular_separation((by_id[identifier].ra, by_id[identifier].de),
                                       (item.ra, item.dec)) < 0.2,
                    f"{what}: far from the OpenNGC position")
            skipped += 1
            continue
        constellation = boundaries.find(item.ra, item.dec, what)
        name = BARNARD_NAMES.get(item.designation)
        if name is not None:
            require(name[0] == constellation,
                    f"{what} ({name[1]}) lies in {constellation}, not {name[0]}")
        created.append(DsoDraft(
            id=identifier, kind="DrkN", origin="barnard", ra=rounded(item.ra, 6),
            de=rounded(item.dec, 6), constellation=constellation,
            names=[name[1]] if name else [], major=item.diameter))
    for designation in BARNARD_NAMES:
        require(any(item.designation == designation for item in objects),
                f"Barnard {designation}: not in the catalogue")
    report.note(f"dsos: Barnard: {len(created)} new dark nebulae, {skipped} already in OpenNGC")
    return created


def lynds_drafts(clouds: Sequence[LyndsCloud], boundaries: ConstellationBoundaries,
                 report: Report) -> list[DsoDraft]:
    """Adds the darkest and the largest Lynds clouds, and the named ones (see the cut above)."""
    by_number = {c.number: c for c in clouds}
    for number in LYNDS_NAMES:
        require(number in by_number, f"LDN {number}: not in the catalogue")
    created = []
    for cloud in clouds:
        keep = (cloud.opacity >= LYNDS_DARKEST_OPACITY
                or cloud.area >= LYNDS_MIN_AREA_SQUARE_DEGREES or cloud.number in LYNDS_NAMES)
        if not keep:
            continue
        what = f"LDN {cloud.number}"
        constellation = boundaries.find(cloud.ra, cloud.dec, what)
        name = LYNDS_NAMES.get(cloud.number)
        if name is not None:
            require(name[0] == constellation,
                    f"{what} ({name[1]}) lies in {constellation}, not {name[0]}")
        created.append(DsoDraft(
            id=f"LDN{cloud.number}", kind="DrkN", origin="lynds", ra=rounded(cloud.ra, 6),
            de=rounded(cloud.dec, 6), constellation=constellation,
            names=[name[1]] if name else [], major=rounded(cloud.diameter, 2),
            opacity=cloud.opacity))
    report.note(f"dsos: Lynds: {len(created)} of {len(clouds)} clouds (opacity {LYNDS_DARKEST_OPACITY} "
                f"or at least {LYNDS_MIN_AREA_SQUARE_DEGREES:g} square degree, or named)")
    return created


def open_cluster_drafts(clusters: Sequence[OpenClusterRecord], drafts: Mapping[str, DsoDraft],
                        boundaries: ConstellationBoundaries, report: Report) -> list[DsoDraft]:
    """Adds the large Collinder, Melotte, Trumpler and Stock clusters the catalog lacks.

    ``drafts`` are the OpenNGC objects by row name. A cluster that one of them already carries as
    a designation (Melotte 22 is the Pleiades, Melotte 25 the Hyades) is not added again.
    """
    by_designation = {c.designation: c for c in clusters}
    known = {designation for draft in drafts.values() for designation in draft.designations()}
    for designation in list(OPEN_CLUSTER_NAMES) + list(OPEN_CLUSTER_IDENTIFICATIONS):
        require(designation in by_designation, f"{designation}: not in the Dias catalogue")
    created, recognized = [], 0
    for cluster in clusters:
        if not OPEN_CLUSTER_MIN_SIZE_ARCMIN <= cluster.diameter <= OPEN_CLUSTER_MAX_SIZE_ARCMIN:
            continue
        what = cluster.designation
        row_name = OPEN_CLUSTER_IDENTIFICATIONS.get(what)
        if row_name is not None:
            target = present(drafts.get(row_name), f"{what}: {row_name} is not in the catalog")
            require(angular_separation((cluster.ra, cluster.dec), (target.ra, target.de))
                    <= cluster.diameter / 120.0, f"{what}: far from {row_name}")
            target.cat.append(cluster.object_id)
            target.cat.sort(key=_cat_sort_key)
            recognized += 1
            continue
        if cluster.object_id in known:
            recognized += 1
            continue
        constellation = boundaries.find(cluster.ra, cluster.dec, what)
        name = OPEN_CLUSTER_NAMES.get(what)
        if name is not None:
            require(name[0] == constellation,
                    f"{what} ({name[1]}) lies in {constellation}, not {name[0]}")
        created.append(DsoDraft(
            id=cluster.object_id, kind="OCl", origin="dias", ra=rounded(cluster.ra, 6),
            de=rounded(cluster.dec, 6), constellation=constellation,
            names=[name[1]] if name else [], major=cluster.diameter))
    report.note(f"dsos: Dias: {len(created)} large clusters added, {recognized} already in the catalog")
    return created


# ------------------------------------------------------------------------------------------
# Prominence
# ------------------------------------------------------------------------------------------

def dso_prominence(draft: DsoDraft, showpieces: frozenset[str]) -> int:
    """How conspicuous an object is, from 1 (showpiece) to 4 (obscure).

    1. Showpiece: Messier and Caldwell objects, the hand-picked :data:`SHOWPIECES`, and anything
       brighter than magnitude 4.
    2. Prominent: brighter than magnitude 8; named objects brighter than magnitude 10 or larger
       than 30'; nebulae of at least 60', and Sharpless regions of at least 60' when of
       brightness class 2 or 3 (also when they are an NGC/IC object); named dark nebulae and
       Barnard objects of at least 3 degrees; Dias clusters of at least 2 degrees.
    3. Notable: everything the first selection rule picked (so no object of the first release
       is unlisted); any other named object; nebulae of at least 10'; Sharpless regions of at
       least 30', or 10' when of the brightest class; Barnard objects of at least 1 degree;
       Lynds clouds that are at least 3 degrees across, or opaque (class 6) and at least 20'
       across; open clusters and associations of at least 30'.
    4. Obscure: the rest. Found by search and drawn at narrow fields only.

    Plain stars (`*`, `**`, a few named entries inherited from NGC/IC) are never above 3. Dark
    nebulae have no magnitude and are rated by name, size and, for Lynds clouds, opacity. A size is
    the major axis in arcminutes.
    """
    size = draft.major or 0.0
    magnitude = draft.magnitude
    named = bool(draft.names)
    is_dark = draft.kind == "DrkN"
    is_nebula = draft.kind in NEBULA_TYPES and not is_dark
    if draft.messier is not None or draft.caldwell is not None or draft.id in showpieces:
        return 1
    if draft.kind in PLAIN_STAR_TYPES:
        return 3 if draft.legacy else 4
    if magnitude is not None and magnitude <= PROMINENCE_SHOWPIECE_MAGNITUDE:
        return 1
    if magnitude is not None and magnitude <= PROMINENCE_BRIGHT_MAGNITUDE:
        return 2
    if named and ((magnitude is not None and magnitude <= PROMINENCE_NOTABLE_MAGNITUDE)
                  or size >= PROMINENCE_NOTABLE_CLUSTER_ARCMIN):
        return 2
    sharpless_size = draft.sharpless_size or 0.0
    if sharpless_size >= PROMINENCE_LARGE_NEBULA_ARCMIN and (draft.sharpless_brightness or 0) >= 2:
        return 2
    if is_nebula and size >= PROMINENCE_LARGE_NEBULA_ARCMIN and draft.origin == "openngc":
        return 2
    if is_dark and named:
        return 2
    if is_dark and draft.origin != "lynds" and size >= PROMINENCE_LARGE_DARK_ARCMIN:
        return 2
    if draft.origin == "dias" and size >= 2 * 60.0:
        return 2
    if draft.legacy or named:
        return 3
    if is_nebula and size >= PROMINENCE_NOTABLE_NEBULA_ARCMIN:
        return 3
    if sharpless_size >= SHARPLESS_NOTABLE_ARCMIN or (
            draft.sharpless_brightness == 3 and sharpless_size >= SHARPLESS_BRIGHT_NOTABLE_ARCMIN):
        return 3
    if draft.origin == "lynds":
        if size >= PROMINENCE_LARGE_DARK_ARCMIN or (
                (draft.opacity or 0) >= LYNDS_DARKEST_OPACITY and size >= LYNDS_NOTABLE_OPAQUE_ARCMIN):
            return 3
    elif is_dark and size >= PROMINENCE_NOTABLE_DARK_ARCMIN:
        return 3
    if draft.kind in CLUSTER_TYPES and size >= PROMINENCE_NOTABLE_CLUSTER_ARCMIN:
        return 3
    return 4


# ------------------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------------------

def draft_item(draft: DsoDraft, prominence: int) -> Item:
    """The JSON object of a draft (keys in the order the file documents)."""
    what = f"object {draft.id}"
    obj: Item = {"id": draft.id}
    if draft.messier is not None:
        obj["m"] = draft.messier
    if draft.ngc:
        obj["ngc"] = draft.ngc
    if draft.ic:
        obj["ic"] = draft.ic
    if draft.cat:
        obj["cat"] = draft.cat
    if draft.names:
        obj["names"] = draft.names
    obj["t"] = draft.kind
    obj["ra"] = draft.ra
    obj["de"] = draft.de
    if draft.constellation:
        obj["c"] = draft.constellation
    for key, value, places, low, high in (
        ("vm", draft.v_mag, 2, -30.0, 40.0), ("bm", draft.b_mag, 2, -30.0, 40.0),
        ("maj", draft.major, 2, 0.0, 100000.0), ("min", draft.minor, 2, 0.0, 100000.0),
        ("pa", draft.position_angle, 1, 0.0, 360.0), ("sb", draft.surface_brightness, 2, 0.0, 40.0),
    ):
        if value is not None:
            require_range(value, low, high, f"{what} {key}")
            obj[key] = rounded(value, places)
    if draft.hubble:
        obj["h"] = draft.hubble
    obj["p"] = prominence
    return obj


_NATURAL_PART = re.compile(r"\d+|\D+")


def _natural_key(identifier: str) -> tuple[tuple[int, int, str], ...]:
    """Sorts ``B2`` before ``B10`` and ``Sh2-9`` before ``Sh2-10``."""
    return tuple((0, int(part), "") if part.isdigit() else (1, 0, part)
                 for part in _NATURAL_PART.findall(identifier))


def _dso_sort_key(obj: Item) -> tuple[int, int, str, tuple[tuple[int, int, str], ...]]:
    """Messier by number, then NGC, then IC by number, then the rest in natural order of the id."""
    identifier = str(obj["id"])
    if "m" in obj:
        return (0, obj["m"], "", ())
    match = re.fullmatch(r"(NGC|IC)(\d+)(.*)", identifier)
    if match:
        return (1 if match.group(1) == "NGC" else 2, int(match.group(2)), match.group(3), ())
    return (3, 0, "", _natural_key(identifier))


def build_dsos(files: Mapping[tuple[str, str], Path], constellations: ConstellationNames,
               boundaries: ConstellationBoundaries, report: Report) -> list[Item]:
    """Builds the deep-sky catalog (see the module docstring and Tools/README.md for the rules)."""
    rows: dict[str, NgcRow] = {}
    for row in read_ngc_rows(files[OPENNGC_CSV]) + read_ngc_rows(files[OPENNGC_ADDENDUM_CSV]):
        require(row.name not in rows, f"OpenNGC lists {row.name} twice")
        rows[row.name] = row

    for name, (constellation, _) in SUPPLEMENTARY_NAMES.items():
        require(name in rows and rows[name].constellation == constellation
                and rows[name].kind not in EXCLUDED_DSO_TYPES,
                f"supplementary names target {name}, which does not match OpenNGC")
    for name, removed in REMOVED_NAMES.items():
        require(name in rows and set(removed) <= set(rows[name].common_names),
                f"{name} no longer carries {removed}; drop it from REMOVED_NAMES")

    messier: dict[str, int] = {}
    for row in rows.values():
        if row.messier is not None and row.kind not in ("Dup", "NonEx"):
            require(row.messier not in messier.values(),
                    f"Messier {row.messier} is claimed twice (again by {row.name})")
            messier[row.name] = row.messier
    for number, name in MESSIER_OVERRIDES.items():
        if number not in messier.values():
            require(name in rows and rows[name].kind not in EXCLUDED_DSO_TYPES
                    and name not in messier, f"cannot assign M{number} to {name}")
            messier[name] = number
            report.note(f"dsos: M{number} is not a primary OpenNGC object; assigned to {name} "
                        "by the conventional identification")
    designations = _designations(rows)

    forced = set(SHARPLESS_IDENTIFICATIONS.values()) | set(OPEN_CLUSTER_IDENTIFICATIONS.values())
    drafts = openngc_drafts(rows, messier, designations, forced, constellations)
    report.note(f"dsos: OpenNGC: {len(drafts)} objects ({sum(d.legacy for d in drafts.values())} "
                "by the first rule)")
    drop_foreign_numbers(drafts, report)

    new_drafts: list[DsoDraft] = []
    new_drafts += sharpless_drafts(read_sharpless(files[SHARPLESS_DAT]), drafts, boundaries, report)
    new_drafts += barnard_drafts(read_barnard(files[BARNARD_DAT]), drafts, boundaries, report)
    new_drafts += lynds_drafts(read_lynds(files[LYNDS_DAT]), boundaries, report)
    new_drafts += open_cluster_drafts(read_dias(files[DIAS_DAT]), drafts, boundaries, report)

    everything = list(drafts.values()) + new_drafts
    require(len({d.id for d in everything}) == len(everything), "deep-sky object ids are not unique")
    showpieces = frozenset(SHOWPIECES)
    missing = showpieces - {d.id for d in everything}
    require(not missing, f"showpieces are not in the catalog: {sorted(missing)}")

    objects = [draft_item(d, dso_prominence(d, showpieces)) for d in everything]
    objects.sort(key=_dso_sort_key)
    levels = [sum(1 for o in objects if o["p"] == level) for level in range(1, 5)]
    report.note("dsos: prominence 1/2/3/4: " + " / ".join(str(n) for n in levels))
    return objects


# ==========================================================================================
# Milky Way outlines
# ==========================================================================================

Point = tuple[float, float]  # (longitude, latitude) in degrees
Vector = tuple[float, float, float]


def _unit_vector(point: Point) -> Vector:
    longitude, latitude = math.radians(point[0]), math.radians(point[1])
    cos_latitude = math.cos(latitude)
    return (cos_latitude * math.cos(longitude), cos_latitude * math.sin(longitude),
            math.sin(latitude))


def _cross(a: Vector, b: Vector) -> Vector:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a: Vector, b: Vector) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _angle(a: Vector, b: Vector) -> float:
    """Angular distance in radians."""
    return math.atan2(math.sqrt(_dot(_cross(a, b), _cross(a, b))), _dot(a, b))


def _farthest_from_arc(vectors: Sequence[Vector], low: int, high: int) -> tuple[int, float]:
    """Index in ``(low, high)`` farthest from the great-circle arc low -> high, and its distance."""
    a, b = vectors[low], vectors[high]
    normal = _cross(a, b)
    length = math.sqrt(_dot(normal, normal))
    best_index, best_distance = low + 1, -1.0
    if length < 1e-12:  # coincident endpoints: distance from the shared point
        for index in range(low + 1, high):
            distance = _angle(a, vectors[index])
            if distance > best_distance:
                best_index, best_distance = index, distance
        return best_index, best_distance
    normal = (normal[0] / length, normal[1] / length, normal[2] / length)
    toward_b_at_a = _cross(normal, a)  # tangent at a, pointing toward b
    toward_b_at_b = _cross(normal, b)  # tangent at b, pointing beyond b
    for index in range(low + 1, high):
        p = vectors[index]
        if _dot(p, toward_b_at_a) >= 0.0 and _dot(p, toward_b_at_b) <= 0.0:
            distance = math.asin(min(1.0, abs(_dot(p, normal))))  # foot lies on the arc
        else:
            distance = min(_angle(p, a), _angle(p, b))
        if distance > best_distance:
            best_index, best_distance = index, distance
    return best_index, best_distance


def simplify_loop(points: Sequence[Point], tolerance_degrees: float) -> list[Point]:
    """Douglas-Peucker simplification of a closed loop on the sphere.

    ``points`` are (longitude, latitude) degrees without a repeated closing vertex. Distances are
    measured to great-circle arcs, so the result is correct near the poles and for loops that
    circle the whole sky. The first vertex is always kept. Anchors are inserted so that no span
    exceeds :data:`MAX_ARC_CHORD_DEGREES`, which keeps every arc well defined.
    """
    count = len(points)
    if count <= 3:
        return list(points)
    vectors = [_unit_vector(point) for point in points]
    vectors.append(vectors[0])
    cumulative = [0.0]
    for index in range(1, count + 1):
        cumulative.append(cumulative[-1] + _angle(vectors[index - 1], vectors[index]))
    farthest = max(range(1, count), key=lambda index: _angle(vectors[0], vectors[index]))
    anchors = [0, farthest, count]
    max_chord = math.radians(MAX_ARC_CHORD_DEGREES)
    position = 0
    while position < len(anchors) - 1:
        low, high = anchors[position], anchors[position + 1]
        if high - low > 1 and _angle(vectors[low], vectors[high]) > max_chord:
            middle = bisect.bisect_left(cumulative, (cumulative[low] + cumulative[high]) / 2,
                                        low, high)
            anchors.insert(position + 1, min(max(middle, low + 1), high - 1))
        else:
            position += 1
    tolerance = math.radians(tolerance_degrees)
    keep = set(anchors)
    stack = list(zip(anchors, anchors[1:]))
    while stack:
        low, high = stack.pop()
        if high - low < 2:
            continue
        index, distance = _farthest_from_arc(vectors, low, high)
        if distance > tolerance:
            keep.add(index)
            stack.append((low, index))
            stack.append((index, high))
    return [points[index] for index in sorted(keep) if index < count]


def _orientation(a: Point, b: Point, c: Point) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _edges_cross(a: Point, b: Point, c: Point, d: Point) -> bool:
    """True if the planar segments ab and cd cross at an interior point of both."""
    return (_orientation(c, d, a) * _orientation(c, d, b) < 0
            and _orientation(a, b, c) * _orientation(a, b, d) < 0)


def _ring_edges(ring: Sequence[Point]) -> list[tuple[Point, Point]]:
    return [(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]


def _first_crossing(ring: Sequence[Point]) -> tuple[int, int] | None:
    """Indices of the first two non-adjacent edges of a planar ring that cross, if any."""
    edges = _ring_edges(ring)
    for i, (a, b) in enumerate(edges):
        for j in range(i + 2, len(edges)):
            if (i, j) != (0, len(edges) - 1) and _edges_cross(a, b, *edges[j]):
                return i, j
    return None


def ring_is_simple(ring: Sequence[Point]) -> bool:
    """True if no two non-adjacent edges of the planar ring cross."""
    return _first_crossing(ring) is None


def split_at_crossings(ring: Sequence[Point]) -> list[list[Point]]:
    """Splits a self-intersecting ring into simple loops covering the same even-odd region.

    The source contours contain a few figure-eight loops; each crossing becomes a vertex of
    both resulting loops.
    """
    pending, loops = [list(ring)], []
    while pending:
        current = pending.pop()
        crossing = _first_crossing(current)
        if crossing is None:
            loops.append(current)
            continue
        i, j = crossing
        edges = _ring_edges(current)
        (a, b), (c, d) = edges[i], edges[j]
        fraction = _orientation(c, d, a) / (_orientation(c, d, a) - _orientation(c, d, b))
        point = (a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1]))
        pending.append([point] + current[i + 1:j + 1])
        pending.append(current[:i + 1] + [point] + current[j + 1:])
    return loops


def _bounding_box(ring: Sequence[Point]) -> tuple[float, float, float, float]:
    longitudes, latitudes = [p[0] for p in ring], [p[1] for p in ring]
    return min(longitudes), min(latitudes), max(longitudes), max(latitudes)


def point_in_ring(point: Point, ring: Sequence[Point]) -> bool:
    """Even-odd ray casting in the (longitude, latitude) plane."""
    x, y = point
    inside = False
    for (x1, y1), (x2, y2) in _ring_edges(ring):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


def nesting_depth(rings: Sequence[Sequence[Point]]) -> list[int]:
    """For each ring, the number of other rings that contain it (planar, non-crossing rings).

    A ring is judged by a majority vote of sample vertices, which keeps rings that merely touch
    another ring at a shared vertex from being misclassified.
    """
    boxes = [_bounding_box(ring) for ring in rings]
    depths = []
    for index, ring in enumerate(rings):
        samples = ring[::max(1, len(ring) // 7)]
        depth = 0
        for other_index, other in enumerate(rings):
            outer, inner = boxes[other_index], boxes[index]
            if other_index == index or not (outer[0] <= inner[0] and outer[1] <= inner[1]
                                            and inner[2] <= outer[2] and inner[3] <= outer[3]):
                continue
            votes = sum(point_in_ring(point, other) for point in samples)
            depth += votes * 2 > len(samples)
        depths.append(depth)
    return depths


def signed_area(ring: Sequence[Point]) -> float:
    """Planar shoelace area in square degrees; positive for counter-clockwise rings."""
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in _ring_edges(ring)) / 2.0


def _longitude_step(a: float, b: float) -> float:
    """Signed longitude change from a to b along the shorter way."""
    step = (b - a) % 360.0
    return step - 360.0 if step > 180.0 else step


def _drop_repeats(points: Sequence[Point], *, closed: bool = True) -> list[Point]:
    """Removes consecutive duplicate points (and a closing copy of the first, if ``closed``)."""
    cleaned: list[Point] = []
    for point in points:
        if not cleaned or point != cleaned[-1]:
            cleaned.append(point)
    if closed and len(cleaned) > 1 and cleaned[0] == cleaned[-1]:
        cleaned.pop()
    return cleaned


def _cut_at_seam(loop: Sequence[Point]) -> list[Point]:
    """Cuts a loop that circles the sky at longitude +-180 into a west-to-east planar curve.

    The curve runs from (-180, y) to (+180, y), where y is the latitude at which the loop crosses
    the seam; both ends are the same point on the sphere.
    """
    count = len(loop)
    crossings = [i for i in range(count) if abs(loop[(i + 1) % count][0] - loop[i][0]) > 180.0]
    require(len(crossings) == 1, f"sky-spanning loop crosses longitude 180 {len(crossings)} times")
    index = crossings[0]
    before, after = loop[index], loop[(index + 1) % count]
    eastward = before[0] > after[0]  # +180 side -> -180 side
    seam = 180.0 if eastward else -180.0
    unwrapped = after[0] + (360.0 if eastward else -360.0)
    fraction = (seam - before[0]) / (unwrapped - before[0])
    latitude = before[1] + fraction * (after[1] - before[1])
    path = [loop[(index + 1 + k) % count] for k in range(count)]  # starts right after the seam
    if eastward:
        curve = [(-180.0, latitude)] + path + [(180.0, latitude)]
    else:
        curve = [(180.0, latitude)] + path + [(-180.0, latitude)]
        curve.reverse()
    return _drop_repeats(curve, closed=False)


def _seam_points(longitude: float, start: float, end: float) -> list[Point]:
    """Intermediate points (exclusive of both ends) along a meridian, for faithful projection."""
    segments = max(1, math.ceil(abs(end - start) / MILKY_WAY_SEAM_STEP_DEGREES))
    return [(longitude, start + (end - start) * k / segments) for k in range(1, segments)]


def _band_ring(loops: Sequence[Sequence[Point]]) -> list[Point]:
    """Joins the two sky-spanning loops of a level into one planar ring.

    The region between two loops that circle the whole sky is an annulus; as a planar polygon it
    needs one cut, made along the meridian at right ascension 180 degrees (the seam of the
    source data). The cut has zero width and its edges are subdivided so that any projection
    renders it as the same meridian.
    """
    require(len(loops) == 2, f"expected two sky-spanning loops, found {len(loops)}")
    curves = []
    for loop in loops:
        curve = _cut_at_seam(loop)
        closing = curve[-1]
        curves.append(simplify_loop(curve[:-1], MILKY_WAY_TOLERANCE_DEGREES) + [closing])
    curves.sort(key=lambda curve: curve[0][1], reverse=True)  # northern loop first
    upper, lower = curves
    require(upper[0][1] - lower[0][1] > 0.1, "sky-spanning loops coincide at the seam")
    ring = list(upper)
    ring += _seam_points(180.0, upper[-1][1], lower[-1][1])
    ring += list(reversed(lower))
    ring += _seam_points(-180.0, lower[0][1], upper[0][1])
    require(ring_is_simple(ring), "the Milky Way band outline crosses itself")
    return ring


def _output_ring(ring: Sequence[Point]) -> list[list[float]] | None:
    """Converts a planar ring to right ascension / declination; ``None`` if it degenerated."""
    points = _drop_repeats([(rounded(wrap_degrees(lon), MILKY_WAY_DECIMALS),
                             rounded(lat, MILKY_WAY_DECIMALS)) for lon, lat in ring])
    return [[lon, lat] for lon, lat in points] if len(points) >= 3 else None


def build_milky_way_level(level: int, rings: Sequence[Sequence[Point]], report: Report) -> Item:
    """Simplifies one brightness level and splits its rings into fills and holes.

    The source rings are contours of equal brightness, so a ring nested inside another one is a
    hole, a ring inside a hole an island, and so on. Rings are therefore classified by nesting
    depth, and wound counter-clockwise (fills) or clockwise (holes) so that both the even-odd
    and the non-zero fill rule produce the same picture.
    """
    planar: list[list[Point]] = []
    loops: list[list[Point]] = []
    for ring in rings:
        turn = sum(_longitude_step(a[0], b[0]) for a, b in _ring_edges(ring))
        turns = round(turn / 360.0)
        require(abs(turn - 360.0 * turns) < 1.0 and abs(turns) <= 1,
                f"level {level}: ring winds {turn / 360.0:.2f} times around the sky")
        if turns:
            loops.append(list(ring))
        else:
            planar.append(list(ring))

    simplified: list[list[Point]] = [_band_ring(loops)] if loops else []
    dropped = 0
    for ring in planar:
        for loop in split_at_crossings(simplify_loop(ring, MILKY_WAY_TOLERANCE_DEGREES)):
            if len(loop) < 3 or abs(signed_area(loop)) < MILKY_WAY_TOLERANCE_DEGREES ** 2:
                dropped += 1
            else:
                simplified.append(loop)
    if dropped:
        report.note(f"milkyway: level {level}: {dropped} rings smaller than the tolerance dropped")

    fills: list[list[list[float]]] = []
    holes: list[list[list[float]]] = []
    for ring, depth in zip(simplified, nesting_depth(simplified)):
        if (signed_area(ring) > 0.0) != (depth % 2 == 0):
            ring = ring[::-1]
        converted = _output_ring(ring)
        if converted is not None:
            (holes if depth % 2 else fills).append(converted)
    entry: Item = {"level": level, "polygons": fills}
    if holes:
        entry["holes"] = holes
    return entry


def build_milky_way(path: Path, report: Report) -> list[Item]:
    """Converts d3-celestial's five Milky Way outlines."""
    levels = []
    for feature in _features(load_json(path), "mw.json"):
        match = present(re.fullmatch(r"ol(\d)", str(feature.get("id"))),
                        f"mw.json: unexpected feature id {feature.get('id')!r}")
        geometry = feature.get("geometry")
        require(isinstance(geometry, dict) and geometry.get("type") == "MultiPolygon"
                and isinstance(geometry.get("coordinates"), list), "mw.json: not a MultiPolygon")
        rings: list[list[Point]] = []
        for polygon in geometry["coordinates"]:
            require(isinstance(polygon, list), "mw.json: malformed polygon")
            for raw_ring in polygon:
                require(isinstance(raw_ring, list), "mw.json: malformed ring")
                points = _drop_repeats([_geo_point(raw, "Milky Way") for raw in raw_ring])
                require(len(points) >= 3 and all(lon <= 180.0 for lon, _ in points),
                        "mw.json: degenerate ring or longitude beyond 180 degrees")
                rings.append(points)
        levels.append(build_milky_way_level(int(match.group(1)), rings, report))
    levels.sort(key=lambda entry: entry["level"])
    return levels


# ==========================================================================================
# Validation
# ==========================================================================================

def _check_position(item: Item, what: str) -> None:
    require_range(item["ra"], 0.0, 360.0, f"{what} ra", upper_open=True)
    require_range(item["de"], -90.0, 90.0, f"{what} de")


def validate_stars(stars: Sequence[Item], abbreviations: set[str]) -> None:
    """Sanity checks on the star catalog."""
    require(7000 <= len(stars) <= 12000, f"unexpected star count {len(stars)}")
    seen: dict[str, set[int]] = {"hip": set(), "hr": set(), "hyg": set()}
    for star in stars:
        _check_position(star, f"star {star.get('n', star.get('hip', star.get('hr')))}")
        require(star["c"] in abbreviations, f"star with unknown constellation {star['c']!r}")
        require(any(key in star for key in seen), "star without any id")
        for key, values in seen.items():
            if key in star:
                require(star[key] not in values, f"duplicate {key} {star[key]}")
                values.add(star[key])
    magnitudes = [star["m"] for star in stars]
    require(magnitudes == sorted(magnitudes), "stars are not sorted by magnitude")

    by_hip = {star["hip"]: star for star in stars if "hip" in star}
    for hip, (ra, de) in REFERENCE_STARS.items():
        star = by_hip.get(hip, {})
        require(abs(star.get("ra", math.inf) - ra) < REFERENCE_TOLERANCE_DEGREES
                and abs(star.get("de", math.inf) - de) < REFERENCE_TOLERANCE_DEGREES,
                f"HIP {hip} is missing or misplaced")
    require(by_hip[32349].get("n") == "Sirius", "HIP 32349 is not Sirius")
    require(by_hip[11767].get("n") == "Polaris", "Polaris (HIP 11767) is not named")
    require(by_hip.get(27989, {}).get("n") == "Betelgeuse", "Betelgeuse (HIP 27989) is not named")
    require(by_hip.get(27989, {}).get("b") == "α", "Betelgeuse lacks its Bayer letter")
    require(by_hip.get(87937, {}).get("n") is not None, "Barnard's Star is not named")


# Caldwell objects that must be where the Caldwell list puts them (Moore 1995): Caldwell number
# -> NGC/IC designation of the object. A sample of the 109, spread over every kind of object.
CALDWELL_CHECKS: dict[int, tuple[str, int]] = {
    1: ("NGC", 188), 2: ("NGC", 40), 4: ("NGC", 7023), 5: ("IC", 342), 6: ("NGC", 6543),
    11: ("NGC", 7635), 13: ("NGC", 457), 19: ("IC", 5146), 20: ("NGC", 7000),
    27: ("NGC", 6888), 31: ("IC", 405), 33: ("NGC", 6992), 34: ("NGC", 6960),
    38: ("NGC", 4565), 39: ("NGC", 2392), 49: ("NGC", 2238), 55: ("NGC", 7009),
    63: ("NGC", 7293), 65: ("NGC", 253), 77: ("NGC", 5128), 80: ("NGC", 5139),
    92: ("NGC", 3372), 94: ("NGC", 4755), 103: ("NGC", 2070), 106: ("NGC", 104),
}
# Required deep-sky objects of the new catalogues: (id, constellation, a name it carries).
CATALOGUE_CHECKS: tuple[tuple[str, str, str], ...] = (
    ("B33", "Ori", "Horsehead Nebula"), ("B72", "Oph", "Snake Nebula"),
    ("B78", "Oph", "Pipe Nebula"), ("LDN1622", "Ori", "Boogeyman Nebula"),
    ("LDN1235", "Cep", "Shark Nebula"), ("Sh2-129", "Cep", "Flying Bat Nebula"),
    ("Sh2-240", "Tau", "Spaghetti Nebula"), ("Sh2-132", "Cep", "Lion Nebula"),
    ("C9", "Cep", "Cave Nebula"), ("Mel20", "Per", "Alpha Persei Cluster"),
    ("Cl399", "Vul", "Coathanger Asterism"),
)
# Positions (J2000, degrees) of a few objects from the sources' own coordinates, to pin the
# precession of the B1900.0, B1950.0 and B1875.0 positions: id -> (ra, dec, tolerance).
POSITION_CHECKS: dict[str, tuple[float, float, float]] = {
    "B33": (85.2458, -2.4583, 0.05),        # Horsehead, OpenNGC
    "Sh2-129": (317.94, 59.96, 0.3),        # Sharpless' own center; the nebula spans 2.3 degrees
    "Sh2-274": (112.28, 13.26, 0.1),        # Medusa Nebula (Abell 21), SIMBAD 07 29 08 +13 14.2
    "Sh2-290": (133.55, 8.92, 0.1),         # Abell 31, SIMBAD 08 54 13 +08 53.9
    "LDN1622": (88.50, 1.83, 0.4),          # the Boogeyman Nebula, about 05 54 +01 50
}
DSO_MAX_BYTES = 600 * 1024


def validate_dsos(objects: Sequence[Item], abbreviations: set[str],
                  files: Mapping[tuple[str, str], Path],
                  boundaries: ConstellationBoundaries) -> None:
    """Sanity checks on the deep-sky catalog."""
    require(1500 <= len(objects) <= 6000, f"unexpected deep-sky object count {len(objects)}")
    by_id = {obj["id"]: obj for obj in objects}
    require(len(by_id) == len(objects), "deep-sky ids are not unique")
    for obj in objects:
        _check_position(obj, f"object {obj['id']}")
        require(obj["t"] in DSO_TYPES, f"{obj['id']}: bad type {obj['t']!r}")
        require("c" in obj and obj["c"] in abbreviations, f"{obj['id']}: bad constellation")
        require(PROMINENCE_RANGE[0] <= obj["p"] <= PROMINENCE_RANGE[1],
                f"{obj['id']}: prominence {obj['p']} out of range")
        require(len(obj.get("names", [])) == len(set(obj.get("names", []))),
                f"{obj['id']}: repeated names")
    messier = sorted(obj["m"] for obj in objects if "m" in obj)
    require(messier == list(range(1, MESSIER_COUNT + 1)),
            f"Messier objects are not exactly 1..{MESSIER_COUNT}: {messier}")
    m31 = by_id.get("M31", {})
    require(abs(m31.get("ra", 0.0) - 10.6848) < 1e-3 and abs(m31.get("de", 0.0) - 41.2690) < 1e-3,
            "M31 is missing or misplaced")
    require("M42" in by_id, "M42 is missing")

    designations = {(prefix, number) for obj in objects for prefix, key in
                    (("NGC", "ngc"), ("IC", "ic")) for number in obj.get(key, [])}
    names = {name.casefold() for obj in objects for name in obj.get("names", [])}
    for kind, value in REQUIRED_DSOS:
        found = value.casefold() in names if kind == "name" else (kind, value) in designations
        require(found, f"required target missing: {kind} {value}")

    # No NGC/IC number and no cross-catalogue designation belongs to two objects.
    owners: dict[str, str] = {}
    for obj in objects:
        claimed = ([f"NGC{n}" for n in obj.get("ngc", [])] + [f"IC{n}" for n in obj.get("ic", [])]
                   + list(obj.get("cat", [])))
        if re.fullmatch(r"(?:M|NGC|IC)\d+", obj["id"]) is None:
            claimed.append(obj["id"])
        for designation in claimed:
            require(designation not in owners,
                    f"{designation} belongs to {owners.get(designation)} and {obj['id']}")
            owners[designation] = obj["id"]
        for designation in obj.get("cat", []):
            require(re.fullmatch(r"(?:C|Sh2-|Mel|Cl|Tr|St)\d{1,3}", designation) is not None,
                    f"{obj['id']}: unexpected cross designation {designation!r}")

    caldwell = sorted(int(d[1:]) for d in owners if re.fullmatch(r"C\d+", d))
    require(caldwell == list(range(1, CALDWELL_COUNT + 1)),
            f"Caldwell objects are not exactly 1..{CALDWELL_COUNT}: {caldwell}")
    for number, (prefix, ngc_number) in CALDWELL_CHECKS.items():
        holder = by_id[owners[f"C{number}"]]
        require(ngc_number in holder.get({"NGC": "ngc", "IC": "ic"}[prefix], []),
                f"Caldwell {number} should be {prefix} {ngc_number}, it is {holder['id']}")
        require(holder["p"] == 1, f"Caldwell {number} is not a showpiece")
    require(all(obj["p"] == 1 for obj in objects if "m" in obj), "a Messier object is not a showpiece")
    sharpless = sorted(int(d[4:]) for d in owners if d.startswith("Sh2-"))
    require(sharpless == list(range(1, 314)), "Sharpless regions 1..313 are not each in exactly one object")
    barnard_rows = read_barnard(files[BARNARD_DAT])
    require(all(f"B{b.designation}" in owners for b in barnard_rows),
            "a Barnard object is missing")
    lynds = [obj for obj in objects if obj["id"].startswith("LDN")]
    require(250 <= len(lynds) <= 600, f"unexpected number of Lynds clouds: {len(lynds)}")
    for obj_id, constellation, name in CATALOGUE_CHECKS:
        obj = by_id.get(obj_id)
        require(obj is not None and obj.get("c") == constellation and name in obj.get("names", []),
                f"{obj_id} ({name}) is missing, misplaced or unnamed")
    for obj_id, (ra, dec, tolerance) in POSITION_CHECKS.items():
        obj = by_id.get(obj_id)
        require(obj is not None and angular_separation((ra, dec), (obj["ra"], obj["de"])) <= tolerance,
                f"{obj_id} is missing or misplaced")
    require(by_id["Sh2-274"]["t"] == "PN" and by_id["Sh2-240"]["t"] == "SNR",
            "Sharpless type overrides are missing")

    # The constellation lookup must reproduce OpenNGC's own constellations for its objects.
    openngc_const = {row.name: row.constellation for row in
                     read_ngc_rows(files[OPENNGC_CSV]) + read_ngc_rows(files[OPENNGC_ADDENDUM_CSV])}
    checked = 0
    for obj in objects:
        stem = re.sub(r"^([A-Za-z]+)(\d+)$", lambda m: f"{m.group(1)}{int(m.group(2)):04d}", obj["id"])
        original = openngc_const.get(stem)
        if original and obj["id"][0] in "NI":
            expected = OPENNGC_CONSTELLATION_ALIASES.get(original.strip().lower(), original.strip())
            require(boundaries.find(obj["ra"], obj["de"], obj["id"]) == expected,
                    f"{obj['id']}: the constellation boundaries disagree with OpenNGC ({expected})")
            checked += 1
    require(checked > 1000, f"only {checked} constellations cross-checked")


def validate_constellations(entries: Sequence[Item]) -> None:
    """Sanity checks on the constellation catalog."""
    require(len(entries) == 88, f"expected 88 constellations, got {len(entries)}")
    require(len({entry["abbr"] for entry in entries}) == 88, "constellation abbreviations repeat")
    for entry in entries:
        positions = [entry["label"]] + [point for line in entry["lines"] for point in line]
        for ra, dec in positions:
            require_range(ra, 0.0, 360.0, f"{entry['abbr']} ra", upper_open=True)
            require_range(dec, -90.0, 90.0, f"{entry['abbr']} dec")


def validate_milky_way(levels: Sequence[Item], size: int) -> None:
    """Sanity checks on the Milky Way outlines."""
    require([level["level"] for level in levels] == [1, 2, 3, 4, 5], "levels must be 1...5")
    require(size < MILKY_WAY_MAX_BYTES,
            f"milkyway.json is {size} bytes (limit {MILKY_WAY_MAX_BYTES})")
    for level in levels:
        require(bool(level["polygons"]), f"level {level['level']} has no polygons")
        for ring in level["polygons"] + level.get("holes", []):
            require(len(ring) >= 3, "Milky Way ring with fewer than three vertices")
            for ra, dec in ring:
                require_range(ra, 0.0, 360.0, "Milky Way ra", upper_open=True)
                require_range(dec, -90.0, 90.0, "Milky Way dec")


# ==========================================================================================
# Orchestration
# ==========================================================================================

@dataclass
class Report:
    """Collects build notes and counts for the final summary."""

    notes: list[str] = field(default_factory=list)

    def note(self, message: str) -> None:
        self.notes.append(message)


def build_documents(lock: Lock, files: Mapping[tuple[str, str], Path], report: Report
                    ) -> dict[str, bytes]:
    """Builds and validates every output file; returns file name -> bytes."""
    constellations = ConstellationNames.iau()
    abbreviations = set(constellations.canonical.values())

    def source_line(key: str, derived_from: str) -> str:
        entry = lock.sources[key]
        return f"{entry.title} ({entry.repo} @ {entry.commit[:12]}){derived_from}"

    def header(key: str, derived_from: str, *, generated: bool) -> dict[str, object]:
        document: dict[str, object] = {
            "schema": SCHEMA_VERSION,
            "source": source_line(key, derived_from),
            "license": lock.sources[key].license_id,
        }
        if generated:
            document["generated"] = lock.locked_on
        return document

    stars = build_stars(files[HYG_CSV], constellations, report)
    validate_stars(stars, abbreviations)
    boundaries = ConstellationBoundaries.read(files[ROMAN_DAT], constellations)
    dsos = build_dsos(files, constellations, boundaries, report)
    validate_dsos(dsos, abbreviations, files, boundaries)
    entries = build_constellations(files[D3_CONSTELLATIONS], files[D3_LINES], report)
    validate_constellations(entries)
    levels = build_milky_way(files[D3_MILKY_WAY], report)

    documents = {
        "stars.json": render_document(
            header("hyg", ", derived from the Hipparcos, Yale Bright Star and Gliese catalogs",
                   generated=True), "stars", stars),
        "dsos.json": render_document(
            header("openngc", ", compiled from NED, HyperLEDA, SIMBAD, HEASARC and H. Corwin's "
                   "NGC/IC notes; with the catalogues of Sharpless (1959), Barnard (1927), Lynds "
                   "(1962) and Dias et al. (2002) as distributed by CDS VizieR "
                   "(" + ", ".join(f"{lock.sources[k].url[len(CDS_FTP):]}"
                                   for k in ("sharpless", "barnard", "lynds", "dias", "roman"))
                   + ")", generated=True), "objects", dsos),
        "constellations.json": render_document(
            header("d3celestial", "; IAU names and genitives checked against the IAU list",
                   generated=False), "constellations", entries),
        "milkyway.json": render_document(
            header("d3celestial", ", from the Milky Way Outline Catalog by Jose R. Vieira",
                   generated=False), "levels", levels),
    }
    validate_milky_way(levels, len(documents["milkyway.json"]))
    require(len(documents["dsos.json"]) <= DSO_MAX_BYTES,
            f"dsos.json is {len(documents['dsos.json'])} bytes (limit {DSO_MAX_BYTES})")
    report.note(f"counts: {len(stars)} stars, {len(dsos)} deep-sky objects, "
                f"{len(entries)} constellations, "
                f"{sum(len(lv['polygons']) + len(lv.get('holes', [])) for lv in levels)} "
                "Milky Way rings")
    return documents


def write_atomically(target: Path, data: bytes) -> None:
    """Writes a file so that readers never see a partial one."""
    partial = target.with_name(target.name + ".part")
    partial.write_bytes(data)
    os.replace(partial, target)


def write_documents(out_dir: Path, documents: Mapping[str, bytes]) -> None:
    """Writes the output files."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, data in documents.items():
        write_atomically(out_dir / name, data)


def differences(out_dir: Path, documents: Mapping[str, bytes]) -> list[str]:
    """Names of output files that are missing or differ from the freshly built ones."""
    stale = []
    for name, data in documents.items():
        target = out_dir / name
        if not target.is_file() or target.read_bytes() != data:
            stale.append(name)
    return stale


def check_attribution(lock: Lock, attribution: Path) -> None:
    """Warns if ATTRIBUTION.md does not mention a locked commit or a CDS catalogue directory."""
    try:
        text = attribution.read_text(encoding="utf-8")
    except OSError:
        warn(f"{attribution} not found; attributions cannot be cross-checked")
        return
    for key, entry in lock.sources.items():
        if entry.commit:
            if entry.commit not in text:
                warn(f"ATTRIBUTION.md does not mention {key} commit {entry.commit}; update it")
        else:
            catalogue = entry.url[len(CDS_FTP):]
            if catalogue not in text:
                warn(f"ATTRIBUTION.md does not mention the CDS catalogue {catalogue} ({key}); "
                     "update it")


def parse_arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    default_lock = Path(__file__).resolve().with_name("sources.lock.json")
    parser = argparse.ArgumentParser(
        description="Build Lodestar's bundled star, deep-sky, constellation and Milky Way "
                    "catalogs from pinned upstream data.")
    parser.add_argument("--out", type=Path, required=True,
                        help="directory receiving stars.json, dsos.json, constellations.json, "
                             "milkyway.json")
    parser.add_argument("--cache", type=Path, required=True,
                        help="directory for downloaded sources (created if needed)")
    parser.add_argument("--lock", type=Path, default=default_lock,
                        help="lock file (default: sources.lock.json next to this script)")
    parser.add_argument("--refresh-lock", action="store_true",
                        help="resolve each source's ref to a commit again, re-download and "
                             "rewrite the lock (only after the build succeeds)")
    parser.add_argument("--ref", action="append", default=[], metavar="KEY=REF",
                        help="with --refresh-lock: track REF (branch or tag) for source KEY; "
                             f"keys: {', '.join(SOURCES_BY_KEY)}")
    parser.add_argument("--only", action="append", default=[], metavar="KEY",
                        help="with --refresh-lock: refresh just the source KEY (repeatable) and "
                             "keep the other entries and the lock date; keys: "
                             f"{', '.join(SOURCES_BY_KEY)}")
    parser.add_argument("--check", action="store_true",
                        help="do not write; fail if --out differs from a fresh build")
    arguments = parser.parse_args(argv)
    arguments.overrides = {}
    for item in arguments.ref:
        key, separator, ref = item.partition("=")
        if not separator or key not in SOURCES_BY_KEY or not _REF.fullmatch(ref):
            parser.error(f"--ref expects KEY=REF with KEY in {sorted(SOURCES_BY_KEY)}: {item!r}")
        arguments.overrides[key] = ref
    if arguments.overrides and not arguments.refresh_lock:
        parser.error("--ref requires --refresh-lock")
    if arguments.only and not arguments.refresh_lock:
        parser.error("--only requires --refresh-lock")
    for key in arguments.only:
        if key not in SOURCES_BY_KEY:
            parser.error(f"--only expects one of {sorted(SOURCES_BY_KEY)}: {key!r}")
    if arguments.refresh_lock and arguments.check:
        parser.error("--check cannot be combined with --refresh-lock")
    return arguments


def main(argv: Sequence[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        if arguments.refresh_lock:
            lock = refresh_lock(load_previous_lock(arguments.lock), arguments.overrides,
                                arguments.cache, arguments.only)
        else:
            require(arguments.lock.is_file(),
                    f"{arguments.lock} does not exist; create it with --refresh-lock")
            lock = read_lock(arguments.lock)
        files = fetch_locked_files(lock, arguments.cache)
        report = Report()
        documents = build_documents(lock, files, report)

        if arguments.check:
            stale = differences(arguments.out, documents)
            require(not stale, f"out of date: {', '.join(stale)}; rebuild without --check")
        else:
            write_documents(arguments.out, documents)
            if arguments.refresh_lock:
                write_atomically(arguments.lock, lock_to_json(lock).encode("utf-8"))
        check_attribution(lock, Path(__file__).resolve().parent.parent / "ATTRIBUTION.md")
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for message in report.notes:
        print(message)
    for name, data in documents.items():
        print(f"{name}: {len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
