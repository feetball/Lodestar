"""Writes CometsTestData.kt/.swift (small extracts of real MPC and JPL records used as fixtures).

Inputs, all downloaded 2026-10-18 into the working directory (use /dev/shm, the disk is small):
  curl -O https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt
  curl -r 0-400000 -o MPCORB_head.txt https://www.minorplanetcenter.net/iau/MPCORB/MPCORB.DAT
  curl -O https://www.minorplanetcenter.net/iau/MPCORB/NEA.txt
  curl -o sbdb_4.json 'https://ssd-api.jpl.nasa.gov/sbdb.api?des=4&phys-par=1&full-prec=1'   # likewise sbdb_1.json (des=1),
      sbdb_12P.json (12P), sbdb_C_2F2023_20A3.json (C/2023 A3), sbdb_1P.json (1P), sbdb_3I.json (3I), sbdb_2024_20YR4.json (2024 YR4)
  python3 -I fetch_mpc_cases.py   # mpc_cases.json
Run with `python3 -I`.
"""
import json, re

comet_lines = open("CometEls.txt").read().split("\n")
def comet(match, nth=0):
    found = [l for l in comet_lines if match in l]
    return found[nth]

CASES = [
    ("hale_bopp", "C/1995 O1 (Hale-Bopp)"),
    ("tsuchinshan_atlas", "C/2023 A3 (Tsuchinshan-ATLAS)"),
    ("pons_brooks", "12P/Pons-Brooks"),
    ("halley", "1P/Halley"),
    ("encke", "2P/Encke"),
    ("biela_a", "3D-A/Biela"),
    ("perrine_mrkos", "18D/Perrine-Mrkos"),
    ("schwassmann_wachmann_3_bt", "73P-BT/Schwassmann-Wachmann"),
    ("ikeya_murakami_b", "332P-B/Ikeya-Murakami"),
    ("oumuamua", "1I/`Oumuamua"),
    ("borisov", "2I/Borisov"),
    ("atlas_3i", "3I/ATLAS"),
    ("siding_spring", "C/2013 A1 (SidingSpring)"),
    ("asteroid_like", "A/2018 W3"),
    ("unnamed_periodic", "P/2026 N2"),
    ("hartley_iras", "161P/Hartley-IRAS"),
    ("gehrels", "78P/Gehrels"),
    ("schwassmann_wachmann", "29P/Schwassmann-Wachmann"),
    ("bernardinelli_bernstein", "C/2014 UN271 (Bernardinelli-Bernstein)"),
    ("wierzchos", "C/2024 E1 (Wierzchos)"),
    ("leonard", "P/2026 R2 (Leonard)"),
]
def exact(title):
    # the title column starts at col 103 and is followed by spaces
    for l in comet_lines:
        if len(l) >= 103 and l[102:158].strip() == title:
            return l
    raise KeyError(title)
comets = [(k, exact(t)) for k, t in CASES]

mp_head = open("MPCORB_head.txt").read().split("\n")
nea = open("NEA.txt").read().split("\n")
def mpline(lines, key):
    for l in lines:
        if l.startswith(key): return l
    raise KeyError(key)
asteroids = [
    ("ceres", mpline(mp_head, "00001 ")),
    ("vesta", mpline(mp_head, "00004 ")),
    ("eros", mpline(nea, "00433 ")),
    ("apophis", mpline(nea, "99942 ")),
    ("bennu", mpline(nea, "A1955 ")),
    ("yr4_2024", mpline(nea, "K24Y04R")),
    ("unknown_h", mpline(nea, "J91T00T")),
    ("assumed_eccentricity", mpline(nea, "K06WD0O")),
    ("numbered_unnamed", mpline(nea, "K2411 ")),
    ("year_end_epoch_aa", mpline(nea, "K24A00A")),
]

def trim_json(path):
    d = json.load(open(path))
    keep_phys = {"H", "G", "M1", "K1", "M2", "K2", "PC", "diameter"}
    o = d["orbit"]
    one = lambda x: json.dumps(x, ensure_ascii=True)
    def items(entries, indent):
        pad = " " * indent
        return "[\n" + ",\n".join(pad + one(e) for e in entries) + "\n" + pad[:-1] + "]" if entries else "[]"
    orbit_scalars = ", ".join(f"{one(k)}: {one(o[k])}" for k in ("epoch", "equinox", "orbit_id", "soln_date") if k in o)
    text = "{\n"
    text += f' "object": {one(d["object"])},\n'
    text += f' "signature": {one(d["signature"])},\n'
    text += f' "orbit": {{{orbit_scalars},\n  "elements": {items(o["elements"], 3)},\n  "model_pars": {items(o.get("model_pars", []), 3)}}},\n'
    text += f' "phys_par": {items([p for p in d.get("phys_par", []) if p["name"] in keep_phys], 2)}\n}}'
    json.loads(text)
    return text

jsons = [
    ("vesta", "sbdb_4.json"), ("ceres", "sbdb_1.json"), ("pons_brooks", "sbdb_12P.json"),
    ("tsuchinshan_atlas", "sbdb_C_2F2023_20A3.json"), ("halley", "sbdb_1P.json"), ("atlas_3i", "sbdb_3I.json"),
    ("yr4_2024", "sbdb_2024_20YR4.json"),
]
json_texts = [(k, trim_json(f)) for k, f in jsons]

mpc_cases = json.load(open("mpc_cases.json"))
KEYS = [("161P", "hartley_iras"), ("78P", "gehrels"), ("29P", "schwassmann_wachmann"), ("UN271", "bernardinelli_bernstein"), ("E1", "wierzchos"), ("R2", "leonard")]

def camel(prefix, key):
    parts = key.split("_")
    return prefix + "".join(p.capitalize() if i >= 0 else p for i, p in enumerate(parts))

def kt_str(s):
    assert '"""' not in s and "$" not in s
    return '"""' + s + '"""'
def sw_str(s):
    assert '"""' not in s and "\\" not in s
    return '"""\n' + s + '\n"""' if "\n" in s else '"' + s.replace('"', '\\"') + '"'

def write_kotlin():
    o = []
    o.append("""package net.kuecker.lodestar.kit.comets

/**
 * Real records used as test fixtures (small extracts, not whole files):
 * - comet lines: `CometEls.txt` of the Minor Planet Center, https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt,
 *   downloaded 2026-10-18 (Last-Modified 08:15 GMT), all elements osculating at 2026-10-17;
 * - asteroid lines: `MPCORB.DAT` (Ceres, Vesta) and `NEA.txt`, https://www.minorplanetcenter.net/iau/MPCORB/, downloaded 2026-10-18;
 * - JSON: answers of https://ssd-api.jpl.nasa.gov/sbdb.api?des=...&phys-par=1&full-prec=1 (2026-10-18), reduced to the
 *   members the parser reads plus a few neighbours;
 * - Horizons rows for the comets above: https://ssd.jpl.nasa.gov/api/horizons.api, OBSERVER table, CENTER=500@399,
 *   TLIST (UT) 2461331.5 and 2461361.5 (2026-10-18 and 2026-11-17), QUANTITIES 1,9,19,20,23,24,27.
 */
internal object CometsTestData {""")
    for k, l in comets:
        o.append(f"    /** MPC comet line of {l[102:158].strip()}. */")
        o.append(f"    val {camel('comet', k)}: String =\n        {kt_str(l)}")
    for k, l in asteroids:
        o.append(f"    /** MPC minor-planet line of {l[166:194].strip() or l[0:7].strip()}. */")
        o.append(f"    val {camel('asteroid', k)}: String =\n        {kt_str(l)}")
    for k, t in json_texts:
        o.append(f"    /** Small-Body Database answer for {k}. */")
        o.append(f"    val {camel('json', k)}: String = {kt_str(chr(10) + t)}.trimStart()")
    o.append("""
    /** A row of the Horizons table for an MPC comet: astrometric position and the distances. */
    class MpcRow(val dayOffset: Double, val ra: Double, val dec: Double, val sunDistance: Double, val earthDistance: Double,
        val elongation: Double, val phaseAngle: Double, val tailPositionAngle: Double, val magnitude: Double)
""")
    for pk, name in KEYS:
        rows = mpc_cases[pk]["rows"]
        phys = {k: v for k, v in mpc_cases[pk]["phys"]}
        items = []
        for off, r in zip([0.0, 30.0], rows):
            items.append(f"MpcRow({off}, {float(r['R.A.___(ICRF)'])!r}, {float(r['DEC____(ICRF)'])!r}, {float(r['r'])!r}, {float(r['delta'])!r}, {float(r['S-O-T'])!r}, {float(r['S-T-O'])!r}, {float(r['PsAng'])!r}, {float(r['T-mag'])!r})")
        o.append(f"    /** Horizons (JPL magnitude parameters M1={phys['M1']}, K1={phys['k1']}) for {name}. */")
        o.append(f"    val {camel('horizons', name)}: List<MpcRow> = listOf(\n        " + ",\n        ".join(items) + ",\n    )")
    o.append("}")
    return "\n".join(o) + "\n"

def write_swift():
    o = []
    o.append("""import Foundation

/// Real records used as test fixtures (small extracts, not whole files):
/// - comet lines: `CometEls.txt` of the Minor Planet Center, https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt,
///   downloaded 2026-10-18 (Last-Modified 08:15 GMT), all elements osculating at 2026-10-17;
/// - asteroid lines: `MPCORB.DAT` (Ceres, Vesta) and `NEA.txt`, https://www.minorplanetcenter.net/iau/MPCORB/, downloaded 2026-10-18;
/// - JSON: answers of https://ssd-api.jpl.nasa.gov/sbdb.api?des=...&phys-par=1&full-prec=1 (2026-10-18), reduced to the
///   members the parser reads plus a few neighbours;
/// - Horizons rows for the comets above: https://ssd.jpl.nasa.gov/api/horizons.api, OBSERVER table, CENTER=500@399,
///   TLIST (UT) 2461331.5 and 2461361.5 (2026-10-18 and 2026-11-17), QUANTITIES 1,9,19,20,23,24,27.
enum CometsTestData {""")
    for k, l in comets:
        name = camel("comet", k)
        o.append(f"    /// MPC comet line of {l[102:158].strip()}.")
        o.append(f"    static let {name}: String =\n        {sw_str(l)}")
    for k, l in asteroids:
        o.append(f"    /// MPC minor-planet line of {l[166:194].strip() or l[0:7].strip()}.")
        o.append(f"    static let {camel('asteroid', k)}: String =\n        {sw_str(l)}")
    for k, t in json_texts:
        assert "\\" not in t
        body = "\n".join("    " + x if x else x for x in t.split("\n"))
        o.append(f"    /// Small-Body Database answer for {k}.")
        o.append(f"    static let {camel('json', k)}: String = \"\"\"\n{body}\n    \"\"\"")
    o.append("""
    /// A row of the Horizons table for an MPC comet: astrometric position and the distances.
    struct MpcRow {
        let dayOffset: Double
        let ra: Double
        let dec: Double
        let sunDistance: Double
        let earthDistance: Double
        let elongation: Double
        let phaseAngle: Double
        let tailPositionAngle: Double
        let magnitude: Double
    }
""")
    for pk, name in KEYS:
        rows = mpc_cases[pk]["rows"]
        phys = {k: v for k, v in mpc_cases[pk]["phys"]}
        items = []
        for off, r in zip([0.0, 30.0], rows):
            items.append(f"MpcRow(dayOffset: {off}, ra: {float(r['R.A.___(ICRF)'])!r}, dec: {float(r['DEC____(ICRF)'])!r}, sunDistance: {float(r['r'])!r}, earthDistance: {float(r['delta'])!r}, elongation: {float(r['S-O-T'])!r}, phaseAngle: {float(r['S-T-O'])!r}, tailPositionAngle: {float(r['PsAng'])!r}, magnitude: {float(r['T-mag'])!r})")
        o.append(f"    /// Horizons (JPL magnitude parameters M1={phys['M1']}, K1={phys['k1']}) for {name}.")
        o.append(f"    static let {camel('horizons', name)}: [MpcRow] = [\n        " + ",\n        ".join(items) + ",\n    ]")
    o.append("}")
    return "\n".join(o) + "\n"

open("CometsTestData.kt", "w").write(write_kotlin())
open("CometsTestData.swift", "w").write(write_swift())
print(len(write_kotlin()), len(write_swift()))
