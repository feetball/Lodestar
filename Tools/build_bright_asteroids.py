#!/usr/bin/env python3
"""Builds asteroids.txt, the bright asteroids that both LodestarKit engines ship (Swift and Kotlin).

The file is an extract of the Minor Planet Center's MPCORB.DAT (one line per asteroid, the MPC one-line orbit format
that `MinorPlanetElementsParser` reads): the MPC header, kept as the MPC's licence requires, then the lines of the
asteroids with H of 10.5 or brighter whose best-case peak magnitude is 11.0 or brighter. Lines are copied unchanged.

    best-case peak magnitude = H + 5 log10(r * d)    r = max(q, 0.4226),  d = max(r - 1, 0.5)

q = a (1 - e) is the perihelion distance in AU, r the Sun distance of the best opposition (never below sin 25 degrees:
closer to the Sun than that a body cannot stand 25 degrees from it), d the Earth distance at that opposition (never below
0.5 AU, so that near-Earth asteroids, whose close approaches are rare, are not rated by their best moment). This is the
formula of `SmallBodyBrightness.peakMagnitudeEstimate` for an asteroid at zero phase angle, so every asteroid the cut keeps
can reach magnitude 11 in some opposition and no asteroid left out can. The absolute magnitude cap keeps out the faint
near-Earth asteroids that the 0.5 AU floor would otherwise let in. The result is about 215 asteroids (44 kB): the
main-belt asteroids from (4) Vesta (5.2) down to magnitude 11, plus the two large near-Earth asteroids (433) Eros and
(1036) Ganymed.

The source, https://www.minorplanetcenter.net/iau/MPCORB/MPCORB.DAT.gz (94 MB, gzip), is rewritten by the MPC every day and
there is no archive, so a snapshot is pinned by its sha256 in `Tools/asteroids.lock.json` and re-pinned with --refresh-lock.
With the pinned snapshot the file is rebuilt byte for byte; without it --check still verifies the shipped files against the
sha256 of the output that the lock records.

Python 3.9 or newer, standard library only; run it with -I (isolated mode). The download needs 94 MB: point --cache at a
RAM disk (/dev/shm) when the disk is tight, and delete the cache afterwards.

    python3 -I Tools/build_bright_asteroids.py --refresh-lock --cache /dev/shm/asteroids      # new snapshot, new files
    python3 -I Tools/build_bright_asteroids.py --source MPCORB.DAT.gz                         # rebuild from a pinned snapshot
    python3 -I Tools/build_bright_asteroids.py --check                                        # verify the shipped files, offline

Licence: MPC orbit data may be included in software if the header is kept and the Minor Planet Center is credited; see
ATTRIBUTION.md.
"""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import math
import os
import sys
import urllib.request

SOURCE_URL = "https://www.minorplanetcenter.net/iau/MPCORB/MPCORB.DAT.gz"
PEAK_MAGNITUDE_LIMIT = 11.0
MAXIMUM_ABSOLUTE_MAGNITUDE = 10.5
MINIMUM_SUN_DISTANCE = 0.4226  # sin(25 degrees), as SmallBodyBrightness.minimumSunDistanceAU
MINIMUM_EARTH_DISTANCE = 0.5  # as SmallBodyBrightness.minimumAsteroidEarthDistanceAU
MAXIMUM_BYTES = 60_000
MAXIMUM_HEADER_LINES = 100

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_LOCK = os.path.join(HERE, "asteroids.lock.json")
DEFAULT_OUTPUTS = [
    os.path.join(ROOT, "LodestarKit", "Sources", "LodestarKit", "Resources", "asteroids.txt"),
    os.path.join(ROOT, "android", "lodestar-kit", "src", "main", "resources", "net", "kuecker", "lodestar", "kit",
                 "catalog", "asteroids.txt"),
]


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def peak_magnitude(h, a, e):
    """The best-case peak magnitude of an asteroid with absolute magnitude h, semi-major axis a and eccentricity e."""
    sun_distance = max(a * (1.0 - e), MINIMUM_SUN_DISTANCE)
    earth_distance = max(sun_distance - 1.0, MINIMUM_EARTH_DISTANCE)
    return h + 5.0 * math.log10(sun_distance * earth_distance)


def open_text(path):
    raw = open(path, "rb")
    magic = raw.read(2)
    raw.seek(0)
    stream = gzip.GzipFile(fileobj=raw) if magic == b"\x1f\x8b" else raw
    return io.TextIOWrapper(stream, encoding="latin-1", newline="\n")


def extract(path):
    """Returns (header lines, selected lines) of an MPCORB.DAT[.gz]; the header ends with the line of dashes."""
    header, selected = [], []
    with open_text(path) as stream:
        for line in stream:
            line = line.rstrip("\r\n")
            if len(header) < MAXIMUM_HEADER_LINES and not (header and header[-1].startswith("-----")):
                header.append(line)
                continue
            if len(line) < 103:
                continue
            try:
                h = float(line[8:13])
                a = float(line[92:103])
                e = float(line[70:79])
            except ValueError:
                continue
            if h >= 90 or not (a > 0 and 0 <= e < 1):
                continue
            if h <= MAXIMUM_ABSOLUTE_MAGNITUDE and peak_magnitude(h, a, e) <= PEAK_MAGNITUDE_LIMIT:
                selected.append(line.rstrip())
    if not header or not header[-1].startswith("-----"):
        sys.exit("error: no line of dashes ends the MPCORB header; is this MPCORB.DAT?")
    if not selected:
        sys.exit("error: no asteroid passed the selection")
    return header, selected


def render(header, selected, source_sha256, source_date):
    lines = [
        "BRIGHT ASTEROIDS FOR LODESTAR: an extract of the Minor Planet Center orbit database (MPCORB.DAT)",
        f"Source: {SOURCE_URL}, file dated {source_date}, sha256 {source_sha256}",
        f"Selection: H <= {MAXIMUM_ABSOLUTE_MAGNITUDE} and best-case peak magnitude H + 5 log10(r d) <= {PEAK_MAGNITUDE_LIMIT}, "
        f"r = max(q, {MINIMUM_SUN_DISTANCE}), d = max(r - 1, {MINIMUM_EARTH_DISTANCE}); {len(selected)} lines, copied unchanged",
        "Built by Tools/build_bright_asteroids.py. Elements osculate at the epoch of each line (columns 21-25).",
        "",
    ]
    lines += [line.rstrip() for line in header]
    lines += selected
    text = "\n".join(lines) + "\n"
    try:
        text.encode("ascii")
    except UnicodeEncodeError as error:
        sys.exit(f"error: the extract is not plain ASCII: {error}")
    if len(text) > MAXIMUM_BYTES:
        sys.exit(f"error: the extract is {len(text)} bytes, more than {MAXIMUM_BYTES}")
    return text


def download(cache):
    os.makedirs(cache, exist_ok=True)
    partial = os.path.join(cache, "MPCORB.DAT.gz.part")
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "lodestar-asteroid-generator"})
    with urllib.request.urlopen(request, timeout=120) as response, open(partial, "wb") as out:
        modified = response.headers.get("Last-Modified", "")
        while True:
            block = response.read(1 << 20)
            if not block:
                break
            out.write(block)
    digest = sha256_of(partial)
    final = os.path.join(cache, f"MPCORB-{digest[:12]}.DAT.gz")
    os.replace(partial, final)
    return final, digest, modified


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--source", help="a local MPCORB.DAT or MPCORB.DAT.gz (must be the pinned snapshot unless --refresh-lock)")
    parser.add_argument("--source-modified", default="", help="with --source and --refresh-lock: the file's Last-Modified header")
    parser.add_argument("--cache", default=os.path.join(HERE, ".cache", "asteroids"), help="where --refresh-lock downloads to")
    parser.add_argument("--out", action="append", help="output file (repeatable); default: the Swift and Kotlin resources")
    parser.add_argument("--lock", default=DEFAULT_LOCK)
    parser.add_argument("--check", action="store_true", help="only verify the shipped files against the lock; writes nothing")
    parser.add_argument("--refresh-lock", action="store_true", help="pin the current MPC file (or --source) and rebuild")
    args = parser.parse_args()
    outputs = args.out or [path for path in DEFAULT_OUTPUTS if os.path.isdir(os.path.dirname(path))]
    lock = json.load(open(args.lock)) if os.path.exists(args.lock) else None

    if args.check and not args.source:
        if lock is None:
            sys.exit("error: no lock file")
        for path in outputs:
            if sha256_of(path) != lock["output"]["sha256"]:
                sys.exit(f"MISMATCH {path}")
            print(f"ok {path}")
        return

    if not args.source and not args.refresh_lock:
        sys.exit("error: give --source (the pinned snapshot), --refresh-lock or --check")
    if args.source and not args.refresh_lock:
        if lock is None or sha256_of(args.source) != lock["source"]["sha256"]:
            sys.exit("error: --source is not the pinned snapshot; use --refresh-lock to pin it")
    if args.refresh_lock and not args.source:
        source, source_sha256, modified = download(args.cache)
    else:
        source = args.source
        source_sha256 = sha256_of(source)
        modified = args.source_modified if args.refresh_lock else lock["source"]["lastModified"]
    source_date = modified or "unknown date"
    if modified:
        try:
            parsed = datetime.datetime.strptime(modified, "%a, %d %b %Y %H:%M:%S GMT")
            source_date = parsed.strftime("%Y-%m-%d %H:%M GMT")
        except ValueError:
            pass
    header, selected = extract(source)
    text = render(header, selected, source_sha256, source_date)
    data = text.encode("ascii")
    output_sha256 = hashlib.sha256(data).hexdigest()

    if args.check:
        for path in outputs:
            if open(path, "rb").read() != data:
                sys.exit(f"MISMATCH {path}")
            print(f"ok {path}")
        return
    for path in outputs:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as out:
            out.write(data)
        print(f"wrote {path}: {len(selected)} asteroids, {len(data)} bytes")
    if args.refresh_lock:
        new_lock = {
            "schema": 1,
            "lockedOn": datetime.date.today().isoformat(),
            "source": {
                "url": SOURCE_URL,
                "sha256": source_sha256,
                "bytes": os.path.getsize(source),
                "lastModified": modified,
                "license": "MPC orbit data: keep the MPCORB header, credit the Minor Planet Center",
            },
            "selection": {
                "peakMagnitudeLimit": PEAK_MAGNITUDE_LIMIT,
                "maximumAbsoluteMagnitude": MAXIMUM_ABSOLUTE_MAGNITUDE,
                "minimumSunDistanceAU": MINIMUM_SUN_DISTANCE,
                "minimumEarthDistanceAU": MINIMUM_EARTH_DISTANCE,
                "count": len(selected),
            },
            "output": {"sha256": output_sha256, "bytes": len(data)},
        }
        with open(args.lock, "w") as out:
            json.dump(new_lock, out, indent=2)
            out.write("\n")
        print(f"pinned {args.lock}")


if __name__ == "__main__":
    main()
