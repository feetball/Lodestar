#!/usr/bin/env python3
"""Builds the sky catalogs that ship inside Lodestar.

The script downloads a handful of open astronomical data files from GitHub, each pinned to an
immutable commit and verified against the sha256 digest recorded in ``sources.lock.json``, and
converts them into the compact JSON resources bundled by ``LodestarKit``:

    stars.json           stars brighter than magnitude 6.5 plus every named star (HYG Database)
    dsos.json            Messier, named and bright NGC/IC objects (OpenNGC)
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
    --check                    build in memory and compare with ``--out`` instead of writing

Only the Python standard library is used. See ``Tools/README.md`` for the full documentation.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import datetime as dt
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
DOWNLOAD_TIMEOUT_SECONDS = 60
MAX_DOWNLOAD_BYTES = 128 * 1024 * 1024

# Stars: everything at or brighter than this visual magnitude, plus every named star.
STAR_MAGNITUDE_LIMIT = 6.5
SUN_HYG_ID = 0
HIPPARCOS_EPOCH = 1991.25
J2000_EPOCH = 2000.0

# Deep-sky objects: catalogue objects pass with V <= 10.0 (or B <= 10.5 when V is unknown).
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
    """An upstream GitHub repository the catalogs are derived from."""

    key: str
    title: str
    repo: str
    default_ref: str
    license_id: str
    files: tuple[SourceFile, ...]


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
)
SOURCES_BY_KEY = {source.key: source for source in SOURCES}

HYG_CSV = ("hyg", "hyg/CURRENT/hygdata_v41.csv")
OPENNGC_CSV = ("openngc", "database_files/NGC.csv")
OPENNGC_ADDENDUM_CSV = ("openngc", "database_files/addendum.csv")
D3_CONSTELLATIONS = ("d3celestial", "data/constellations.json")
D3_LINES = ("d3celestial", "data/constellations.lines.json")
D3_MILKY_WAY = ("d3celestial", "data/mw.json")


@dataclass(frozen=True)
class LockedFile:
    """The pinned digest of one source file."""

    role: str
    sha256: str
    size: int


@dataclass(frozen=True)
class LockedSource:
    """A source resolved to an immutable commit."""

    title: str
    repo: str
    ref: str
    commit: str
    license_id: str
    files: Mapping[str, LockedFile]


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
        sources[source.key] = {
            "title": entry.title,
            "repo": entry.repo,
            "ref": entry.ref,
            "commit": entry.commit,
            "license": entry.license_id,
            "files": {
                path: {"role": f.role, "sha256": f.sha256, "bytes": f.size}
                for path, f in entry.files.items()
            },
        }
    document = {"schema": LOCK_SCHEMA_VERSION, "lockedOn": lock.locked_on, "sources": sources}
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def read_lock(path: Path) -> Lock:
    """Reads and strictly validates the lock file against :data:`SOURCES`."""
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
    require(isinstance(raw_sources, dict) and set(raw_sources) == set(SOURCES_BY_KEY),
            f"{path}: sources do not match the script; run with --refresh-lock")
    sources: dict[str, LockedSource] = {}
    for source in SOURCES:
        raw = raw_sources[source.key]
        require(isinstance(raw, dict), f"{path}: malformed entry for {source.key}")
        require(raw.get("repo") == source.repo and raw.get("license") == source.license_id
                and raw.get("title") == source.title,
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
                                           source.license_id, files)
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
    """Where a source file is cached: ``<cache>/<source>/<commit>/<repo path>``."""
    check_repo_path(path)
    return cache / key / commit / path


def fetch_locked_files(lock: Lock, cache: Path) -> dict[tuple[str, str], Path]:
    """Makes every locked file available in the cache, verifying each against the lock.

    A cached copy is reused only when its digest matches; anything else is downloaded again.
    A download whose digest differs from the lock is deleted and reported: it means upstream
    rewrote history, the lock is stale, or the transfer was tampered with.
    """
    paths: dict[tuple[str, str], Path] = {}
    for source in SOURCES:
        entry = lock.sources[source.key]
        for path, locked in entry.files.items():
            destination = cache_path(cache, source.key, entry.commit, path)
            if destination.is_file() and sha256_of(destination) == locked.sha256:
                paths[(source.key, path)] = destination
                continue
            print(f"downloading {source.key}: {path}", file=sys.stderr)
            digest, size = download(raw_url(entry.repo, entry.commit, path), destination,
                                    locked.size + 1)
            if digest != locked.sha256 or size != locked.size:
                destination.unlink(missing_ok=True)
                raise BuildError(
                    f"{source.key}/{path}: sha256 {digest} ({size} bytes) differs from the lock "
                    f"({locked.sha256}, {locked.size} bytes) at commit {entry.commit}")
            paths[(source.key, path)] = destination
    return paths


def refresh_lock(previous: Lock | None, overrides: Mapping[str, str], cache: Path) -> Lock:
    """Re-resolves every source to a commit, downloads its files and records their digests."""
    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    sources: dict[str, LockedSource] = {}
    for source in SOURCES:
        old = previous.sources[source.key] if previous else None
        ref = overrides.get(source.key) or (old.ref if old else source.default_ref)
        commit = resolve_commit(source.repo, ref)
        files: dict[str, LockedFile] = {}
        for source_file in source.files:
            print(f"downloading {source.key}@{commit[:10]}: {source_file.path}", file=sys.stderr)
            destination = cache_path(cache, source.key, commit, source_file.path)
            digest, size = download(raw_url(source.repo, commit, source_file.path), destination,
                                    MAX_DOWNLOAD_BYTES)
            require(size > 0, f"{source.key}/{source_file.path}: empty file")
            files[source_file.path] = LockedFile(source_file.role, digest, size)
        sources[source.key] = LockedSource(source.title, source.repo, ref, commit,
                                           source.license_id, files)
        if old is not None:
            describe_lock_changes(source.key, old, sources[source.key])
    return Lock(today, sources)


def load_previous_lock(path: Path) -> Lock | None:
    """The existing lock, if usable; a refresh starts from default refs without one."""
    if not path.is_file():
        return None
    try:
        return read_lock(path)
    except BuildError as error:
        warn(f"ignoring the existing lock ({error}); using the default refs")
        return None


def describe_lock_changes(key: str, old: LockedSource, new: LockedSource) -> None:
    """Prints what a refresh changed; legal files get a prominent warning."""
    if old.commit != new.commit:
        print(f"{key}: commit {old.commit[:10]} -> {new.commit[:10]}", file=sys.stderr)
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
# Deep-sky objects (OpenNGC)
# ==========================================================================================

NGC_COLUMNS = ("Name", "Type", "RA", "Dec", "Const", "MajAx", "MinAx", "PosAng", "B-Mag",
               "V-Mag", "SurfBr", "Hubble", "M", "NGC", "IC", "Common names")
_OPENNGC_NAME = re.compile(r"(NGC|IC)(\d{4})")
_OPENNGC_REFERENCE = re.compile(r"(\d{1,4})([A-Za-z]{1,2}|\s?NED\d{2})?")


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
    """The magnitude/size part of the deep-sky selection rule."""
    if has_names:
        return True
    if row.kind in PLAIN_STAR_TYPES:
        return False
    if row.v_mag is not None:
        return row.v_mag <= DSO_VISUAL_MAGNITUDE_LIMIT
    if row.b_mag is not None:
        return row.b_mag <= DSO_BLUE_MAGNITUDE_LIMIT
    return row.kind in NEBULA_TYPES and (row.major_axis or 0.0) >= NEBULA_MIN_SIZE_ARCMIN


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


def build_dsos(ngc_path: Path, addendum_path: Path, constellations: ConstellationNames,
               report: Report) -> list[Item]:
    """Selects and converts OpenNGC objects (see the module docstring for the rule)."""
    rows: dict[str, NgcRow] = {}
    for row in read_ngc_rows(ngc_path) + read_ngc_rows(addendum_path):
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

    objects: list[Item] = []
    for row in rows.values():
        if row.kind in EXCLUDED_DSO_TYPES:
            continue
        number = messier.get(row.name)
        names = _ordered_names(row)
        if number is None and not _qualifies(row, bool(names)):
            continue
        what = f"OpenNGC {row.name}"
        require(row.kind in DSO_TYPES, f"{what}: unexpected type {row.kind!r}")
        right_ascension = right_ascension_degrees(row.ra, f"{what} RA")
        declination = declination_degrees(row.dec, f"{what} Dec")

        obj: Item = {"id": _object_id(row, number)}
        if number is not None:
            obj["m"] = number
        for key, prefix in (("ngc", "NGC"), ("ic", "IC")):
            numbers = designations.get(row.name, {}).get(prefix)
            if numbers:
                obj[key] = numbers
        if names:
            obj["names"] = list(names)
        obj["t"] = row.kind
        obj["ra"] = wrap_degrees(rounded(right_ascension, 6))
        obj["de"] = rounded(declination, 6)
        if row.constellation.strip():
            obj["c"] = constellations.resolve(row.constellation, what,
                                              aliases=OPENNGC_CONSTELLATION_ALIASES)
        for key, value, places, low, high in (
            ("vm", row.v_mag, 2, -30.0, 40.0), ("bm", row.b_mag, 2, -30.0, 40.0),
            ("maj", row.major_axis, 2, 0.0, 100000.0), ("min", row.minor_axis, 2, 0.0, 100000.0),
            ("pa", row.position_angle, 1, 0.0, 360.0), ("sb", row.surface_brightness, 2, 0.0, 40.0),
        ):
            if value is not None:
                require_range(value, low, high, f"{what} {key}")
                obj[key] = rounded(value, places)
        if row.hubble:
            obj["h"] = row.hubble
        objects.append(obj)

    ids = [obj["id"] for obj in objects]
    require(len(ids) == len(set(ids)), "deep-sky object ids are not unique")
    objects.sort(key=_dso_sort_key)
    return objects


def _dso_sort_key(obj: Item) -> tuple[int, int, str]:
    """Messier by number, then NGC, then IC by number, then the rest by id."""
    identifier = str(obj["id"])
    if "m" in obj:
        return (0, obj["m"], "")
    match = re.fullmatch(r"(NGC|IC)(\d+)(.*)", identifier)
    if match:
        return (1 if match.group(1) == "NGC" else 2, int(match.group(2)), match.group(3))
    return (3, 0, identifier)


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


def validate_dsos(objects: Sequence[Item], abbreviations: set[str]) -> None:
    """Sanity checks on the deep-sky catalog."""
    require(300 <= len(objects) <= 3000, f"unexpected deep-sky object count {len(objects)}")
    by_id = {obj["id"]: obj for obj in objects}
    require(len(by_id) == len(objects), "deep-sky ids are not unique")
    for obj in objects:
        _check_position(obj, f"object {obj['id']}")
        require(obj["t"] in DSO_TYPES, f"{obj['id']}: bad type {obj['t']!r}")
        require("c" not in obj or obj["c"] in abbreviations, f"{obj['id']}: bad constellation")
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
    dsos = build_dsos(files[OPENNGC_CSV], files[OPENNGC_ADDENDUM_CSV], constellations, report)
    validate_dsos(dsos, abbreviations)
    entries = build_constellations(files[D3_CONSTELLATIONS], files[D3_LINES], report)
    validate_constellations(entries)
    levels = build_milky_way(files[D3_MILKY_WAY], report)

    documents = {
        "stars.json": render_document(
            header("hyg", ", derived from the Hipparcos, Yale Bright Star and Gliese catalogs",
                   generated=True), "stars", stars),
        "dsos.json": render_document(
            header("openngc", ", compiled from NED, HyperLEDA, SIMBAD, HEASARC and H. Corwin's "
                   "NGC/IC notes", generated=True), "objects", dsos),
        "constellations.json": render_document(
            header("d3celestial", "; IAU names and genitives checked against the IAU list",
                   generated=False), "constellations", entries),
        "milkyway.json": render_document(
            header("d3celestial", ", from the Milky Way Outline Catalog by Jose R. Vieira",
                   generated=False), "levels", levels),
    }
    validate_milky_way(levels, len(documents["milkyway.json"]))
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
    """Warns if ATTRIBUTION.md does not mention a locked commit."""
    try:
        text = attribution.read_text(encoding="utf-8")
    except OSError:
        warn(f"{attribution} not found; attributions cannot be cross-checked")
        return
    for key, entry in lock.sources.items():
        if entry.commit not in text:
            warn(f"ATTRIBUTION.md does not mention {key} commit {entry.commit}; update it")


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
    if arguments.refresh_lock and arguments.check:
        parser.error("--check cannot be combined with --refresh-lock")
    return arguments


def main(argv: Sequence[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        if arguments.refresh_lock:
            lock = refresh_lock(load_previous_lock(arguments.lock), arguments.overrides,
                                arguments.cache)
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
