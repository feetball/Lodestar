#!/usr/bin/env python3
"""Builds lightpollution.bin, the night-lights grid that both LodestarKit engines ship (Swift and Kotlin).

The source is NASA GIBS (Global Imagery Browse Services), layer `VIIRS_Black_Marble` (Black Marble, Suomi NPP VIIRS day/night
band composite), time 2016-01-01, TileMatrixSet `500m`, zoom level 4: 20 x 10 PNG tiles of 512 x 512 pixels, 18 degrees
(28.4 pixels per degree) each, 200 tiles and about 26 MB. The tiles are an 8-bit RGB display rendering: lights are warm and
saturate at 255 in the big cities, while land carries a faint blue base texture (R and G about half of B; up to B = 85 over
ice). The build, step by step:

 1. Fetch the 200 tiles (HTTPS only) and check each against the sha256 and size pinned in `Tools/lightpollution.lock.json`.
 2. Remove the base texture per pixel: k = min(5R // 3, 5G // 3, B, 96), then R -= ceil(0.6 k), G -= ceil(0.6 k), B -= k
    (integer arithmetic). A bluish base pixel becomes black, a lit pixel keeps its warm colour less a small part.
 3. Convert to linear luminance: sRGB decode of each channel, then 0.2126 R + 0.7152 G + 0.0722 B, in [0, 1].
 4. Average into a 0.1 degree grid, 3600 x 1800 cells (row 0 is the northernmost, column 0 starts at 180 W), by exact area
    weighting: one pixel is 45 units wide and one cell 128 (10240 pixels = 3600 cells x 128 / 45).
 5. Quantize to 16 levels on a log scale: level 0 below `LEVEL_FIRST` (0.0025), otherwise the number of the 15 thresholds,
    spaced evenly in the logarithm from `LEVEL_FIRST` to `LEVEL_LAST` (0.4), that the value reaches. Level 0 is dark: it
    holds the ocean, the deserts, the forests and the ice sheets (whose base texture survives step 2 at about 0.002).
 6. Write the file: a 16-byte header, then each row as runs, see FORMAT below. No compression library is needed to read it.

FORMAT (all integers little-endian):
    bytes 0-3   magic "LPM1"
    bytes 4-5   grid width in cells (3600)           bytes 6-7   grid height in cells (1800)
    byte  8     number of levels (16)                byte  9     0
    bytes 10-13 length in bytes of the run data      bytes 14-15 0
    run data    per row, from the north, runs that add up to exactly the width:
                a token byte holds the level in its low nibble and n in its high nibble; n = 0..14 is a run of n + 1 cells;
                n = 15 is followed by a LEB128 integer m (7 bits per byte, low bits first, at most 3 bytes) and is a run of
                16 + m cells.

The source tiles are open data; credit "NASA Worldview / GIBS, Black Marble (VIIRS, Suomi NPP)", see ATTRIBUTION.md. With the
pinned tiles the file is rebuilt byte for byte; --check verifies the shipped files against the sha256 of the output that the
lock records, offline. --report prints the levels, the sky-glow index and the Bortle class of reference places from the
shipped file.

Python 3.9 or newer, standard library only; run it with -I (isolated mode). The tiles need 26 MB: point --cache at a RAM
disk (/dev/shm) when the disk is tight, and delete the cache afterwards.

    python3 -I Tools/build_light_pollution.py --cache /dev/shm/lp --android <Android repo>           # rebuild from the pinned tiles
    python3 -I Tools/build_light_pollution.py --cache /dev/shm/lp --android <Android repo> --refresh-lock   # re-pin the tiles
    python3 -I Tools/build_light_pollution.py --check --android <Android repo>                       # verify the shipped files
    python3 -I Tools/build_light_pollution.py --report                                               # reference places
"""
import argparse
import bisect
import concurrent.futures
import datetime
import hashlib
import json
import math
import os
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib

LAYER = "VIIRS_Black_Marble"
OBSERVATION_TIME = "2016-01-01"
MATRIX_SET = "500m"
ZOOM = 4
TILE_PIXELS = 512
TILE_COLUMNS = 20
TILE_ROWS = 10
TILE_DEGREES = 18
CAPABILITIES_URL = "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/1.0.0/WMTSCapabilities.xml"
TILE_URL = ("https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/%s/default/%s/%s/{z}/{row}/{col}.png"
            % (LAYER, OBSERVATION_TIME, MATRIX_SET))
MAXIMUM_TILE_BYTES = 2_000_000
MAXIMUM_TILE_DECODED_BYTES = TILE_PIXELS * (3 * TILE_PIXELS + 1)

GRID_WIDTH = 3600
GRID_HEIGHT = 1800
# One source pixel is PIXEL_UNITS wide and one grid cell CELL_UNITS: 10240 * 45 == 3600 * 128 and 5120 * 45 == 1800 * 128.
PIXEL_UNITS = 45
CELL_UNITS = 128
LEVEL_COUNT = 16
LEVEL_FIRST = 0.0025
LEVEL_LAST = 0.4
BASE_MAXIMUM = 96
MAGIC = b"LPM1"
HEADER_BYTES = 16
MAXIMUM_BYTES = 1_000_000

# The sky-glow model of the engines (LightPollutionMap.skyGlowIndex), repeated here for --report.
GLOW_RADIUS_KM = 100.0
GLOW_CORE_KM = 5.5
KILOMETERS_PER_DEGREE = 111.195
# The glow index at which Bortle class 2, 3, ... 9 begin (class 1 is below the first), chosen from the reference places.
BORTLE_GLOW_THRESHOLDS = [0.00045, 0.0012, 0.008, 0.02, 0.06, 0.15, 0.3, 0.5]

# name, latitude, longitude, published Bortle class (lowest, highest) or None, and what the value comes from.
# The published values are approximate: sources differ by a class, and a satellite sees emitted light, not the sky.
REFERENCES = [
    ("Cherry Springs State Park, PA", 41.6627, -77.8230, (2, 2), "Bortle 2, IDA Gold-tier dark sky park"),
    ("Death Valley, Badwater", 36.2296, -116.7673, (1, 2), "NPS night sky: Bortle 1-2, IDA Gold-tier"),
    ("Big Bend, Chisos Basin", 29.2706, -103.3010, (1, 2), "NPS night sky: Bortle 1-2, IDA Gold-tier"),
    ("Joshua Tree, Hidden Valley", 34.0125, -116.1672, (2, 3), "NPS night sky: Bortle 2-3 in the park"),
    ("Zselic Starry Sky Park, HU", 46.2125, 17.8689, (3, 3), "IDA park, sky about 21.4 mag/arcsec2, Bortle 3"),
    ("Galloway Forest Park, Loch Trool", 55.0450, -4.4900, (2, 3), "IDA Gold-tier park, Bortle 2-3"),
    ("Mauna Kea summit", 19.8207, -155.4681, (1, 1), "observatory site, about 21.9 mag/arcsec2, Bortle 1"),
    ("Natural Bridges, UT", 37.6020, -110.0140, (1, 1), "first IDA park, about 22.0 mag/arcsec2, Bortle 1"),
    ("Paranal, Chile", -24.6275, -70.4044, (1, 1), "ESO site, Bortle 1"),
    ("Roque de los Muchachos, La Palma", 28.7606, -17.8816, (1, 1), "observatory site, Bortle 1"),
    ("Kielder Observatory, UK", 55.2336, -2.6025, (2, 3), "IDA Gold-tier park, Bortle 2-3"),
    ("McDonald Observatory, TX", 30.6714, -104.0225, (1, 2), "Bortle 1-2"),
    ("Green Bank, WV", 38.4331, -79.8397, (3, 3), "radio quiet zone, Bortle 3"),
    ("Flagstaff, AZ (Lowell Observatory)", 35.2028, -111.6646, (5, 6), "IDA Dark Sky City, suburban sky"),
    ("Boulder, CO", 40.0150, -105.2705, (7, 7), "bright suburban sky"),
    ("Palo Alto, CA", 37.4419, -122.1430, (7, 8), "suburban/urban transition"),
    ("Plano, TX", 33.0198, -96.6989, (7, 8), "suburban/urban transition"),
    ("Munich, Marienplatz", 48.1374, 11.5755, (8, 9), "city sky"),
    ("Cape Town, centre", -33.9249, 18.4241, (8, 9), "city sky"),
    ("London, Trafalgar Square", 51.5080, -0.1281, (9, 9), "inner-city sky, about 18 mag/arcsec2"),
    ("New York, Times Square", 40.7580, -73.9855, (9, 9), "inner-city sky, about 17 mag/arcsec2"),
    ("Las Vegas, the Strip", 36.1147, -115.1728, (9, 9), "inner-city sky"),
    ("Tokyo, Shinjuku", 35.6896, 139.7006, (9, 9), "inner-city sky"),
    ("Pacific Ocean", 0.0, -150.0, (1, 1), "open ocean"),
    ("Sahara", 23.0, 10.0, (1, 1), "empty desert"),
]

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_LOCK = os.path.join(HERE, "lightpollution.lock.json")
SWIFT_OUTPUT = os.path.join(ROOT, "LodestarKit", "Sources", "LodestarKit", "Resources", "lightpollution.bin")
KOTLIN_OUTPUT = os.path.join("lodestar-kit", "src", "main", "resources", "net", "kuecker", "lodestar", "kit", "catalog",
                             "lightpollution.bin")


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def thresholds():
    """The 15 level thresholds: level n is the number of them that a value reaches."""
    return [round(LEVEL_FIRST * (LEVEL_LAST / LEVEL_FIRST) ** (k / (LEVEL_COUNT - 2)), 9) for k in range(LEVEL_COUNT - 1)]


def representatives():
    """The linear luminance that stands for each level in the engines' sky-glow model (level 0 stands for none)."""
    edges = thresholds()
    ratio = edges[1] / edges[0]
    values = [0.0]
    for k, low in enumerate(edges):
        high = edges[k + 1] if k + 1 < len(edges) else low * ratio
        values.append(float("%.4g" % math.sqrt(low * high)))
    return values


# ----------------------------------------------------------------------------------------------------------- download

class HttpsOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.lower().startswith("https://"):
            raise urllib.error.URLError("refusing a redirect that leaves HTTPS: " + newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_tile(url):
    opener = urllib.request.build_opener(HttpsOnly)
    last = None
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "lodestar-light-pollution-generator"})
            with opener.open(request, timeout=60) as response:
                data = response.read(MAXIMUM_TILE_BYTES + 1)
            if len(data) > MAXIMUM_TILE_BYTES:
                sys.exit("error: %s is larger than %d bytes" % (url, MAXIMUM_TILE_BYTES))
            return data
        except (urllib.error.URLError, OSError) as error:
            last = error
            time.sleep(2 * (attempt + 1))
    sys.exit("error: could not download %s: %s" % (url, last))


def tile_keys():
    return ["%d/%d/%d" % (ZOOM, row, col) for row in range(TILE_ROWS) for col in range(TILE_COLUMNS)]


def fetch_tiles(cache, lock, refresh):
    """Returns {key: path} of the verified tiles; with `refresh` also {key: (sha256, bytes)} of what was hashed."""
    os.makedirs(cache, exist_ok=True)
    paths, pins = {}, {}

    def one(key):
        path = os.path.join(cache, key.replace("/", "_") + ".png")
        pinned = None if refresh or lock is None else lock["tiles"].get(key)
        if os.path.exists(path):
            digest = sha256_of(path)
            if refresh or (pinned and digest == pinned["sha256"] and os.path.getsize(path) == pinned["bytes"]):
                return key, path, digest, os.path.getsize(path)
        if not refresh and pinned is None:
            sys.exit("error: tile %s is not in the lock; use --refresh-lock" % key)
        z, row, col = key.split("/")
        data = download_tile(TILE_URL.replace("{z}", z).replace("{row}", row).replace("{col}", col))
        digest = hashlib.sha256(data).hexdigest()
        if pinned and (digest != pinned["sha256"] or len(data) != pinned["bytes"]):
            sys.exit("error: tile %s does not match the lock (sha256 %s); the upstream tile changed" % (key, digest))
        with open(path + ".part", "wb") as out:
            out.write(data)
        os.replace(path + ".part", path)
        return key, path, digest, len(data)

    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        for key, path, digest, size in pool.map(one, tile_keys()):
            paths[key] = path
            pins[key] = (digest, size)
    return paths, pins


# ---------------------------------------------------------------------------------------------------------------- PNG

def decode_png(path):
    """The rows (bytearrays of R, G, B bytes) of an 8-bit RGB, non-interlaced PNG of TILE_PIXELS squared."""
    with open(path, "rb") as stream:
        data = stream.read(MAXIMUM_TILE_BYTES + 1)
    if len(data) > MAXIMUM_TILE_BYTES or data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("error: %s is not a PNG of a usable size" % path)
    position, header, compressed = 8, None, []
    while position + 12 <= len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        crc = struct.unpack(">I", data[position + 8 + length:position + 12 + length])[0]
        if len(body) != length or zlib.crc32(kind + body) != crc:
            sys.exit("error: %s has a corrupt %s chunk" % (path, kind.decode("latin-1")))
        position += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed.append(body)
        elif kind == b"IEND":
            break
    if header != (TILE_PIXELS, TILE_PIXELS, 8, 2, 0, 0, 0):
        sys.exit("error: %s is not a 512 x 512, 8-bit RGB, non-interlaced PNG: %s" % (path, (header,)))
    decompressor = zlib.decompressobj()
    raw = decompressor.decompress(b"".join(compressed), MAXIMUM_TILE_DECODED_BYTES + 1)
    if len(raw) != MAXIMUM_TILE_DECODED_BYTES or decompressor.unconsumed_tail:
        sys.exit("error: %s has image data of an unexpected size" % path)
    stride = 3 * TILE_PIXELS
    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(TILE_PIXELS):
        kind = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride
        if kind == 1:
            for i in range(3, stride):
                line[i] = (line[i] + line[i - 3]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - 3] if i >= 3 else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                left = line[i - 3] if i >= 3 else 0
                above = previous[i]
                corner = previous[i - 3] if i >= 3 else 0
                pa, pb, pc = abs(above - corner), abs(left - corner), abs(left + above - 2 * corner)
                predictor = left if (pa <= pb and pa <= pc) else (above if pb <= pc else corner)
                line[i] = (line[i] + predictor) & 255
        elif kind != 0:
            sys.exit("error: %s uses the unknown PNG filter %d" % (path, kind))
        rows.append(line)
        previous = line
    return rows


def srgb_to_linear(value):
    c = value / 255.0
    return round(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4, 12)


LINEAR = [srgb_to_linear(v) for v in range(256)]


def row_luminance(row):
    """The light-only linear luminance of each pixel of a decoded row, with the land base texture removed."""
    out = []
    for i in range(0, 3 * TILE_PIXELS, 3):
        red, green, blue = row[i], row[i + 1], row[i + 2]
        base = min((5 * red) // 3, (5 * green) // 3, blue, BASE_MAXIMUM)
        red -= (3 * base + 4) // 5
        green -= (3 * base + 4) // 5
        blue -= base
        out.append(0.2126 * LINEAR[red] + 0.7152 * LINEAR[green] + 0.0722 * LINEAR[blue])
    return out


# ---------------------------------------------------------------------------------------------------------------- grid

def overlaps(pixel_count):
    """For each source pixel, the (cell, weight) pairs of the cells it overlaps; weights add up to PIXEL_UNITS."""
    table = []
    for i in range(pixel_count):
        start, end = PIXEL_UNITS * i, PIXEL_UNITS * (i + 1)
        pairs = []
        for cell in range(start // CELL_UNITS, (end - 1) // CELL_UNITS + 1):
            low, high = max(start, CELL_UNITS * cell), min(end, CELL_UNITS * (cell + 1))
            if high > low:
                pairs.append((cell, high - low))
        table.append(pairs)
    return table


def average_grid(paths):
    """The mean light-only luminance per 0.1 degree cell, as a list of GRID_HEIGHT lists of GRID_WIDTH floats."""
    columns = overlaps(TILE_COLUMNS * TILE_PIXELS)
    rows = overlaps(TILE_ROWS * TILE_PIXELS)
    sums = [[0.0] * GRID_WIDTH for _ in range(GRID_HEIGHT)]
    for tile_row in range(TILE_ROWS):
        for tile_col in range(TILE_COLUMNS):
            image = decode_png(paths["%d/%d/%d" % (ZOOM, tile_row, tile_col)])
            for y in range(TILE_PIXELS):
                luminance = row_luminance(image[y])
                partial = {}
                for x in range(TILE_PIXELS):
                    value = luminance[x]
                    if value:
                        for cell, weight in columns[tile_col * TILE_PIXELS + x]:
                            partial[cell] = partial.get(cell, 0.0) + value * weight
                if not partial:
                    continue
                for cell_row, weight in rows[tile_row * TILE_PIXELS + y]:
                    target = sums[cell_row]
                    for cell, total in partial.items():
                        target[cell] += total * weight
    norm = float(CELL_UNITS * CELL_UNITS)
    return [[value / norm for value in row] for row in sums]


def quantize(grid):
    edges = thresholds()
    return [[bisect.bisect_right(edges, value) for value in row] for row in grid]


# ------------------------------------------------------------------------------------------------------------- format

def encode(levels):
    data = bytearray()
    for row in levels:
        i = 0
        while i < len(row):
            value = row[i]
            j = i + 1
            while j < len(row) and row[j] == value:
                j += 1
            run = j - i
            if run <= 15:
                data.append(((run - 1) << 4) | value)
            else:
                data.append(0xF0 | value)
                extra = run - 16
                while True:
                    byte = extra & 0x7F
                    extra >>= 7
                    data.append(byte | (0x80 if extra else 0))
                    if not extra:
                        break
            i = j
    header = MAGIC + struct.pack("<HHBBIH", GRID_WIDTH, GRID_HEIGHT, LEVEL_COUNT, 0, len(data), 0)
    return header + bytes(data)


def decode(blob):
    """The levels of a file as a list of GRID_HEIGHT bytearrays (the same checks as the engines')."""
    if len(blob) < HEADER_BYTES or blob[:4] != MAGIC:
        sys.exit("error: not a lightpollution.bin")
    width, height, count, zero, length, zero2 = struct.unpack("<HHBBIH", blob[4:HEADER_BYTES])
    if (width, height, count, zero, zero2) != (GRID_WIDTH, GRID_HEIGHT, LEVEL_COUNT, 0, 0):
        sys.exit("error: unexpected header")
    if length != len(blob) - HEADER_BYTES:
        sys.exit("error: wrong run data length")
    position, rows = HEADER_BYTES, []
    for _ in range(height):
        row = bytearray()
        while len(row) < width:
            token = blob[position]
            position += 1
            run = (token >> 4) + 1
            if token >> 4 == 15:
                extra, shift = 0, 0
                while True:
                    byte = blob[position]
                    position += 1
                    extra |= (byte & 0x7F) << shift
                    shift += 7
                    if not byte & 0x80:
                        break
                run = 16 + extra
            if (token & 15) >= count or len(row) + run > width:
                sys.exit("error: bad run")
            row.extend(bytes([token & 15]) * run)
        rows.append(row)
    if position != len(blob):
        sys.exit("error: trailing bytes")
    return rows


# ---------------------------------------------------------------------------------------------------------------- model

def cell_of(latitude, longitude):
    row = min(GRID_HEIGHT - 1, max(0, int(math.floor((90.0 - latitude) * 10.0))))
    column = int(math.floor((longitude + 180.0) * 10.0)) % GRID_WIDTH
    return row, column


def glow_index(levels, latitude, longitude):
    """The engines' sky-glow index: the sum over the cells within GLOW_RADIUS_KM of the level's luminance times the cell's
    area (cosine of its latitude) times (distance / GLOW_CORE_KM) to the power -2.5, the distance never below the core."""
    values = representatives()
    row0, column0 = cell_of(latitude, longitude)
    row_span = int(GLOW_RADIUS_KM / (KILOMETERS_PER_DEGREE * 0.1)) + 1
    total = 0.0
    for row in range(max(0, row0 - row_span), min(GRID_HEIGHT - 1, row0 + row_span) + 1):
        centre_latitude = 90.0 - (row + 0.5) * 0.1
        area = math.cos(math.radians(centre_latitude))
        east_west = KILOMETERS_PER_DEGREE * math.cos(math.radians((latitude + centre_latitude) / 2.0))
        north_south = (centre_latitude - latitude) * KILOMETERS_PER_DEGREE
        column_span = min(GRID_WIDTH // 2 - 1, int(GLOW_RADIUS_KM / (max(east_west, 1e-9) * 0.1)) + 1)
        for step in range(-column_span, column_span + 1):
            column = (column0 + step) % GRID_WIDTH
            delta = ((column + 0.5) * 0.1 - 180.0 - longitude + 540.0) % 360.0 - 180.0
            distance = math.hypot(delta * east_west, north_south)
            level = levels[row][column]
            if distance > GLOW_RADIUS_KM or level == 0:
                continue
            ratio = max(distance, GLOW_CORE_KM) / GLOW_CORE_KM
            total += values[level] * area / (ratio * ratio * math.sqrt(ratio))
    return total


def bortle_class(glow):
    return 1 + bisect.bisect_right(BORTLE_GLOW_THRESHOLDS, glow)


def report(levels, strict=False):
    print("%-36s %-7s %5s %9s %6s  %s" % ("place", "Bortle", "level", "glow", "class", "source of the published value"))
    misses = 0
    for name, latitude, longitude, published, source in REFERENCES:
        row, column = cell_of(latitude, longitude)
        glow = glow_index(levels, latitude, longitude)
        estimate = bortle_class(glow)
        inside = published[0] <= estimate <= published[1]
        misses += 0 if inside else 1
        print("%-36s %-7s %5d %9.5f %6d%s %s" % (name, "%d-%d" % published if published[0] != published[1] else published[0],
                                                 levels[row][column], glow, estimate, " " if inside else "*", source))
    print("%d of %d reference places outside their published class (marked *)" % (misses, len(REFERENCES)))
    return misses


def check_sanity(levels):
    """Facts that must hold for any sound build; a failure stops it before a file is written."""
    def level_at(latitude, longitude):
        row, column = cell_of(latitude, longitude)
        return levels[row][column]

    problems = []
    for name, latitude, longitude, expected in (("mid-Pacific", 0.0, -150.0, 0), ("Sahara", 23.0, 10.0, 0),
                                                ("Antarctic plateau", -85.0, 0.0, 0), ("Greenland", 72.0, -40.0, 0)):
        if level_at(latitude, longitude) != expected:
            problems.append("%s should be level %d, is %d" % (name, expected, level_at(latitude, longitude)))
    for name, latitude, longitude in (("New York", 40.7580, -73.9855), ("London", 51.5080, -0.1281),
                                      ("Tokyo", 35.6896, 139.7006), ("Las Vegas", 36.1147, -115.1728),
                                      ("Paris", 48.8566, 2.3522), ("Los Angeles", 34.0522, -118.2437)):
        if level_at(latitude, longitude) < 14:
            problems.append("%s should be level 14 or more, is %d" % (name, level_at(latitude, longitude)))
    lit = sum(1 for row in levels for value in row if value)
    if not 0.005 < lit / (GRID_WIDTH * GRID_HEIGHT) < 0.10:
        problems.append("%.1f%% of the cells are lit" % (100.0 * lit / (GRID_WIDTH * GRID_HEIGHT)))
    if problems:
        sys.exit("error: sanity check failed:\n  " + "\n  ".join(problems))


# ------------------------------------------------------------------------------------------------------------ the lock

def write_lock(path, pins, output_sha256, output_bytes):
    lines = ["{", '  "schema": 1,', '  "lockedOn": "%s",' % datetime.date.today().isoformat(), '  "source": {',
             '    "title": "NASA GIBS, VIIRS Black Marble (Suomi NPP), 2016 composite",',
             '    "layer": "%s",' % LAYER, '    "time": "%s",' % OBSERVATION_TIME,
             '    "tileMatrixSet": "%s",' % MATRIX_SET, '    "zoom": %d,' % ZOOM,
             '    "tilePixels": %d,' % TILE_PIXELS, '    "tileColumns": %d,' % TILE_COLUMNS, '    "tileRows": %d,' % TILE_ROWS,
             '    "tileDegrees": %d,' % TILE_DEGREES,
             '    "capabilities": "%s",' % CAPABILITIES_URL, '    "tileUrl": "%s",' % TILE_URL,
             '    "license": "NASA open data (GIBS, Black Marble): credit NASA Worldview / GIBS, Black Marble (VIIRS, Suomi NPP)"',
             "  },", '  "processing": {',
             '    "baseRemoval": "k = min(5R//3, 5G//3, B, %d); R, G -= ceil(0.6k); B -= k",' % BASE_MAXIMUM,
             '    "luminance": "sRGB decode, 0.2126 R + 0.7152 G + 0.0722 B",',
             '    "grid": "%dx%d cells of 0.1 degree, exact area average",' % (GRID_WIDTH, GRID_HEIGHT),
             '    "levelFirst": %s,' % LEVEL_FIRST, '    "levelLast": %s,' % LEVEL_LAST, '    "levels": %d,' % LEVEL_COUNT,
             '    "thresholds": %s,' % json.dumps(thresholds()), '    "representatives": %s' % json.dumps(representatives()),
             "  },", '  "output": {', '    "sha256": "%s",' % output_sha256, '    "bytes": %d' % output_bytes, "  },",
             '  "tiles": {']
    keys = tile_keys()
    for index, key in enumerate(keys):
        digest, size = pins[key]
        lines.append('    "%s": {"sha256": "%s", "bytes": %d}%s' % (key, digest, size, "," if index + 1 < len(keys) else ""))
    lines += ["  }", "}"]
    with open(path, "w") as out:
        out.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--cache", default=os.path.join(HERE, ".cache", "lightpollution"), help="where the tiles are kept")
    parser.add_argument("--android", default=os.path.join(ROOT, "android"), help="the Android repository (for the Kotlin copy)")
    parser.add_argument("--out", action="append", help="output file (repeatable); default: the Swift and Kotlin resources")
    parser.add_argument("--lock", default=DEFAULT_LOCK)
    parser.add_argument("--check", action="store_true", help="verify the shipped files against the lock; writes nothing")
    parser.add_argument("--refresh-lock", action="store_true", help="download and pin the tiles again, then rebuild")
    parser.add_argument("--report", action="store_true", help="print the reference places from the shipped file")
    args = parser.parse_args()
    outputs = args.out or [SWIFT_OUTPUT] + ([os.path.join(args.android, KOTLIN_OUTPUT)]
                                            if os.path.isdir(os.path.join(args.android, "lodestar-kit")) else [])
    lock = json.load(open(args.lock)) if os.path.exists(args.lock) else None

    if args.report:
        with open(outputs[0], "rb") as stream:
            sys.exit(1 if report(decode(stream.read())) else 0)
    if args.check:
        if lock is None:
            sys.exit("error: no lock file")
        for path in outputs:
            if sha256_of(path) != lock["output"]["sha256"] or os.path.getsize(path) != lock["output"]["bytes"]:
                sys.exit("MISMATCH %s" % path)
            decode(open(path, "rb").read())
            print("ok %s" % path)
        return
    if lock is None and not args.refresh_lock:
        sys.exit("error: no lock file; use --refresh-lock")

    paths, pins = fetch_tiles(args.cache, lock, args.refresh_lock)
    levels = quantize(average_grid(paths))
    check_sanity(levels)
    blob = encode(levels)
    if len(blob) > MAXIMUM_BYTES:
        sys.exit("error: the file is %d bytes, more than %d" % (len(blob), MAXIMUM_BYTES))
    if decode(blob) != [bytearray(row) for row in levels]:
        sys.exit("error: the file does not decode to the grid")
    output_sha256 = hashlib.sha256(blob).hexdigest()
    if not args.refresh_lock and output_sha256 != lock["output"]["sha256"]:
        sys.exit("error: the output (sha256 %s) differs from the lock; use --refresh-lock after a change of the method"
                 % output_sha256)
    for path in outputs:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as out:
            out.write(blob)
        print("wrote %s: %d bytes" % (path, len(blob)))
    if args.refresh_lock:
        write_lock(args.lock, pins, output_sha256, len(blob))
        print("pinned %s" % args.lock)
    report(levels)


if __name__ == "__main__":
    main()
