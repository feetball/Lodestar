#!/usr/bin/env python3
"""Generate WMM2025Coefficients.swift from NOAA's official WMM2025 coefficient file.

Source (work of the U.S. Government, public domain):

    URL      https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip
    SHA-256  2e76569370d081f2cd7919490218bd094ca9afde347b198eff5621e0af460d03   (the zip archive)
    Member   WMM2025COF/WMM.COF
    SHA-256  dfa8597825af4e0b87ff4198a5b4fb661b3c49f4cd090cd0164e0259b075582f   (the member)

Usage (run with -I so that Python ignores the current directory and the environment):

    python3 -I Tools/generate_wmm_coefficients.py                   # download, verify, write
    python3 -I Tools/generate_wmm_coefficients.py --zip PATH        # use a local copy of the zip
    python3 -I Tools/generate_wmm_coefficients.py --check           # fail if the output is stale
    python3 -I Tools/generate_wmm_coefficients.py --output PATH     # write somewhere else

Security model:

* The archive is accepted only if its SHA-256 equals the digest pinned above, so a changed or
  tampered download is rejected before anything is parsed. The download is limited to HTTPS, a
  size cap and a timeout.
* Nothing from the archive is ever executed or extracted to disk: the single expected member is
  read into memory (size-capped, name matched exactly, so path tricks cannot matter) and its
  digest is checked as well.
* WMM.COF is parsed strictly (see ``parse_coefficient_file``). Any deviation from the expected
  layout aborts generation, so malformed input can never produce a plausible-looking table.

The output depends only on the pinned input (no timestamps, no host paths), so ``--check`` is a
reliable freshness test.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import io
import os
import re
import sys
import tempfile
import urllib.request
import zipfile
import zlib
from dataclasses import dataclass
from pathlib import Path

SOURCE_URL = "https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip"
ARCHIVE_SHA256 = "2e76569370d081f2cd7919490218bd094ca9afde347b198eff5621e0af460d03"
MEMBER_NAME = "WMM2025COF/WMM.COF"
MEMBER_SHA256 = "dfa8597825af4e0b87ff4198a5b4fb661b3c49f4cd090cd0164e0259b075582f"

MAX_ARCHIVE_BYTES = 1 << 20
MAX_MEMBER_BYTES = 1 << 16
DOWNLOAD_TIMEOUT_SECONDS = 30

MAX_DEGREE = 12
EXPECTED_ROW_COUNT = MAX_DEGREE * (MAX_DEGREE + 3) // 2  # one row per (n, m), 1 <= n <= 12, 0 <= m <= n
EXPECTED_EPOCH = 2025.0
EXPECTED_MODEL_NAME = "WMM-2025"

# Plausibility bounds, wide enough for any real WMM yet far below anything a corrupt file yields.
MAX_FIELD_COEFFICIENT_NT = 100_000.0
MAX_SECULAR_COEFFICIENT_NT_PER_YEAR = 1_000.0

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "LodestarKit/Sources/LodestarKit/Geomagnetism/WMM2025Coefficients.swift"
)

_NUMBER = r"-?\d{1,6}\.\d{1,3}"
_EPOCH_LINE = re.compile(r"^\s*(\d{4}\.\d)\s+(WMM-\d{4})\s+(\d{2}/\d{2}/\d{4})\s*$")
_ROW_LINE = re.compile(
    r"^\s*(\d{1,2})\s+(\d{1,2})\s+(" + r")\s+(".join([_NUMBER] * 4) + r")\s*$"
)
_TERMINATOR_LINE = re.compile(r"^9{16,}\s*$")


class GenerationError(Exception):
    """Raised when the input does not match the pinned, expected layout."""


@dataclass(frozen=True)
class CoefficientRow:
    """One line of WMM.COF: Gauss coefficients of degree ``n`` and order ``m``.

    The values stay as the text of the file, so no digit is altered on the way to the output.
    """

    n: int
    m: int
    g: str
    h: str
    g_dot: str
    h_dot: str


@dataclass(frozen=True)
class CoefficientFile:
    """The parsed content of WMM.COF."""

    epoch: float
    model_name: str
    release_date: str
    header_line: str
    rows: tuple[CoefficientRow, ...]


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_archive(zip_path: Path | None) -> bytes:
    """Return the pinned archive bytes, from ``zip_path`` or by downloading, after verification."""
    if zip_path is not None:
        with zip_path.open("rb") as handle:
            data = handle.read(MAX_ARCHIVE_BYTES + 1)
    else:
        if not SOURCE_URL.startswith("https://"):
            raise GenerationError("refusing to download over a non-HTTPS URL")
        request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "lodestar-wmm-generator"})
        with urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response:
            data = response.read(MAX_ARCHIVE_BYTES + 1)
    if len(data) > MAX_ARCHIVE_BYTES:
        raise GenerationError(f"archive exceeds {MAX_ARCHIVE_BYTES} bytes")
    digest = sha256_hex(data)
    if digest != ARCHIVE_SHA256:
        raise GenerationError(
            f"archive SHA-256 mismatch: expected {ARCHIVE_SHA256}, got {digest}. "
            "NOAA may have republished the file; review the change before updating the pin."
        )
    return data


def read_member(archive: bytes) -> bytes:
    """Read ``MEMBER_NAME`` from the archive without extracting anything to disk."""
    try:
        with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
            try:
                info = zipped.getinfo(MEMBER_NAME)
            except KeyError:
                raise GenerationError(f"archive has no member {MEMBER_NAME!r}") from None
            if info.file_size > MAX_MEMBER_BYTES:
                raise GenerationError(f"{MEMBER_NAME} is larger than {MAX_MEMBER_BYTES} bytes")
            member = zipped.read(info)
    except (zipfile.BadZipFile, zlib.error, RuntimeError, NotImplementedError) as error:
        raise GenerationError(f"unreadable zip archive: {error}") from error
    digest = sha256_hex(member)
    if digest != MEMBER_SHA256:
        raise GenerationError(f"{MEMBER_NAME} SHA-256 mismatch: expected {MEMBER_SHA256}, got {digest}")
    return member


def _canonical_literal(token: str) -> str:
    """Return the shortest round-tripping decimal literal for ``token``; -0.0 becomes 0.0."""
    value = float(token)
    if value == 0.0:
        return "0.0"
    text = repr(value)
    if "e" in text or "n" in text:  # exponent, inf or nan: not expected in this file
        raise GenerationError(f"unexpected number format: {token!r}")
    return text


def _check_magnitude(name: str, token: str, limit: float, line_number: int) -> None:
    if abs(float(token)) > limit:
        raise GenerationError(f"line {line_number}: {name} = {token} is implausibly large")


def parse_coefficient_file(text: str) -> CoefficientFile:
    """Parse WMM.COF strictly.

    Layout: one epoch line (``2025.0  WMM-2025  11/13/2024``), then one row per (n, m) in order of
    increasing degree and, within a degree, increasing order (``n m g h g-dot h-dot``), then one or
    more terminator lines made only of nines. Blank lines are tolerated between sections; nothing
    else is. The m = 0 rows must have h = h-dot = 0 because there is no sine term for order zero.
    """
    lines = text.splitlines()
    body = iter(enumerate(lines, start=1))

    header = next(((number, line) for number, line in body if line.strip()), None)
    if header is None:
        raise GenerationError("file is empty")
    header_number, header_line = header
    match = _EPOCH_LINE.match(header_line)
    if match is None:
        raise GenerationError(f"line {header_number}: malformed epoch line {header_line!r}")
    epoch = float(match.group(1))
    model_name = match.group(2)
    release_date = match.group(3)
    if epoch != EXPECTED_EPOCH or model_name != EXPECTED_MODEL_NAME:
        raise GenerationError(f"unexpected model {model_name} at epoch {epoch}")

    rows: list[CoefficientRow] = []
    expected_pairs = [(n, m) for n in range(1, MAX_DEGREE + 1) for m in range(n + 1)]
    terminated = False
    for number, line in body:
        if not line.strip():
            continue
        if _TERMINATOR_LINE.match(line):
            terminated = True
            break
        match = _ROW_LINE.match(line)
        if match is None:
            raise GenerationError(f"line {number}: malformed coefficient row {line!r}")
        if len(rows) == len(expected_pairs):
            raise GenerationError(f"line {number}: more than {len(expected_pairs)} coefficient rows")
        n, m = int(match.group(1)), int(match.group(2))
        if (n, m) != expected_pairs[len(rows)]:
            raise GenerationError(f"line {number}: expected degree/order {expected_pairs[len(rows)]}, got {(n, m)}")
        g, h, g_dot, h_dot = match.group(3, 4, 5, 6)
        _check_magnitude("g", g, MAX_FIELD_COEFFICIENT_NT, number)
        _check_magnitude("h", h, MAX_FIELD_COEFFICIENT_NT, number)
        _check_magnitude("g-dot", g_dot, MAX_SECULAR_COEFFICIENT_NT_PER_YEAR, number)
        _check_magnitude("h-dot", h_dot, MAX_SECULAR_COEFFICIENT_NT_PER_YEAR, number)
        if m == 0 and (float(h) != 0.0 or float(h_dot) != 0.0):
            raise GenerationError(f"line {number}: order-zero row has a non-zero h or h-dot")
        rows.append(CoefficientRow(n, m, g, h, g_dot, h_dot))

    if not terminated:
        raise GenerationError("missing terminator line")
    if len(rows) != EXPECTED_ROW_COUNT:
        raise GenerationError(f"expected {EXPECTED_ROW_COUNT} rows, found {len(rows)}")
    for number, line in body:
        if line.strip() and not _TERMINATOR_LINE.match(line):
            raise GenerationError(f"line {number}: unexpected content after the terminator")

    return CoefficientFile(
        epoch=epoch,
        model_name=model_name,
        release_date=release_date,
        header_line=" ".join(header_line.split()),
        rows=tuple(rows),
    )


def render_swift(parsed: CoefficientFile) -> str:
    """Render the Swift source file for ``parsed``."""
    rows = "\n".join(
        "            CoefficientRow(degree: {n}, order: {m}, g: {g}, h: {h}, gDot: {gd}, hDot: {hd}),".format(
            n=row.n,
            m=row.m,
            g=_canonical_literal(row.g),
            h=_canonical_literal(row.h),
            gd=_canonical_literal(row.g_dot),
            hd=_canonical_literal(row.h_dot),
        )
        for row in parsed.rows
    )
    return f"""// WMM2025Coefficients.swift
//
// GENERATED FILE. DO NOT EDIT.
// Regenerate with: python3 -I Tools/generate_wmm_coefficients.py
//
// World Magnetic Model 2025 ({parsed.model_name}), Gauss coefficients to degree and order {MAX_DEGREE}.
// Produced by NOAA National Centers for Environmental Information and the British Geological
// Survey. A work of the U.S. Government, in the public domain.
//
// Source archive : {SOURCE_URL}
// Archive SHA-256: {ARCHIVE_SHA256}
// Member file    : {MEMBER_NAME}
// Member SHA-256 : {MEMBER_SHA256}
// Header line    : {parsed.header_line}
//
// One row per line of WMM.COF: degree n, order m, g and h in nT at the epoch, and their secular
// variation gDot and hDot in nT/yr. A literal -0.0 in the source is written as 0.0.

extension WorldMagneticModel {{
    /// The WMM2025 coefficient set exactly as published by NOAA.
    enum WMM2025Coefficients {{
        /// Reference epoch t0 of the main-field coefficients, in decimal years.
        static let epoch: Double = {parsed.epoch!r}

        /// Gauss coefficients and secular variation, ordered by degree and then by order.
        static let rows: [CoefficientRow] = [
{rows}
        ]
    }}
}}
"""


def write_atomically(path: Path, content: str) -> None:
    """Replace ``path`` with ``content`` so that readers never observe a partial file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
        os.chmod(temporary_name, 0o644)  # mkstemp creates the file readable by its owner only
        os.replace(temporary_name, path)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate WMM2025Coefficients.swift from NOAA's WMM2025COF.zip.")
    parser.add_argument("--zip", type=Path, metavar="PATH", help="use a local copy of WMM2025COF.zip instead of downloading it")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, metavar="PATH", help="Swift file to write (default: %(default)s)")
    parser.add_argument("--check", action="store_true", help="do not write; exit with status 1 if the output file is not up to date")
    arguments = parser.parse_args(argv)

    try:
        member = read_member(read_archive(arguments.zip))
        try:
            text = member.decode("ascii")
        except UnicodeDecodeError as error:
            raise GenerationError(f"{MEMBER_NAME} is not plain ASCII: {error}") from error
        source = render_swift(parse_coefficient_file(text))
    except (GenerationError, OSError, http.client.HTTPException) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if arguments.check:
        try:
            current = arguments.output.read_text(encoding="utf-8")
        except OSError as error:
            print(f"error: cannot read {arguments.output}: {error}", file=sys.stderr)
            return 2
        if current != source:
            print(f"{arguments.output} is out of date; run this script without --check", file=sys.stderr)
            return 1
        print(f"{arguments.output} is up to date")
        return 0

    write_atomically(arguments.output, source)
    print(f"wrote {EXPECTED_ROW_COUNT} coefficient rows to {arguments.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
