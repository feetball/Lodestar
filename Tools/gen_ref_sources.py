"""Writes CometsHorizonsData.kt/.swift from refs.json (gen_refs.py) and topo.json (fetch_topo.py). Run with `python3 -I`."""
import json, re

refs = json.load(open("refs.json"))
for k, v in refs.items(): v["key"] = k

def num(text):
    if text in ("n.a.", "", None): return None
    return float(text)

def lit(x):
    return "null" if x is None else repr(float(x))

# metadata per case
META = {
    "c2023a3": dict(title="C/2023 A3 (Tsuchinshan-ATLAS)", kind="comet", horizons="JPL#113 (Rec #90004799, solution 2026-Jul-28)"),
    "p12": dict(title="12P/Pons-Brooks", kind="comet", horizons="JPL#K242/85 (Rec #90000225, solution 2026-Oct-09)"),
    "halley1986": dict(title="1P/Halley (1986 apparition)", kind="comet", horizons="Rec #90000030 (solution 2025-Nov-21, 8518 observations 1835-1994)"),
    "vesta": dict(title="(4) Vesta", kind="asteroid", horizons="Rec #4 (solution 2021-Apr-13)"),
    "ceres": dict(title="(1) Ceres", kind="asteroid", horizons="Rec #1 (solution 2021-Apr-13)"),
}

def phys(case):
    text = open(f"hz_{case['key']}_elements.txt").read().split("Initial")[0]
    d = {}
    for k, v in re.findall(r"\b(M1|M2|k1|k2|H|G|PHCOF)=\s*([-0-9.na]+)", text):
        if k not in d: d[k] = v
    return d

rows_out = {}
for key, c in refs.items():
    e = c["elements"]
    p = phys(c)
    rows = []
    for off, r in zip(c["offsets"], c["observer"]):
        mag = num(r.get("T-mag", r.get("APmag")))
        nuc = num(r.get("N-mag", "n.a."))
        rows.append(dict(offset=float(off), ra=num(r["R.A.___(ICRF)"]), dec=num(r["DEC____(ICRF)"]),
                         raApp=num(r["R.A.__(a-app)"]), decApp=num(r["DEC___(a-app)"]), mag=mag, nuc=nuc,
                         r=num(r["r"]), delta=num(r["delta"]), elong=num(r["S-O-T"]), phase=num(r["S-T-O"]),
                         psang=num(r["PsAng"])))
    rows_out[key] = dict(meta=META[key], epoch=c["epoch_tdb"], ec=num(e["EC"]), qr=num(e["QR"]), inc=num(e["IN"]),
                         om=num(e["OM"]), w=num(e["W"]), tp=num(e["Tp"]), phys=p, rows=rows)


topo = json.load(open("topo.json"))
TOPO_CASE = {"c2023a3_la": "c2023a3", "halley_sydney": "halley1986", "p12_hawaii": "p12"}

def kotlin_topo():
    out = ["", "    /** A topocentric Horizons row: site (CENTER=coord@399, geodetic), UT Julian Day, apparent RA/DEC and airless azimuth/elevation (QUANTITIES 2,4). */",
           "    class TopocentricRow(",
           "        val caseKey: String,",
           "        val latitude: Double,",
           "        val longitude: Double,",
           "        val elevationMeters: Double,",
           "        val julianDayUT: Double,",
           "        val raApparent: Double,",
           "        val decApparent: Double,",
           "        val azimuth: Double,",
           "        val elevation: Double,",
           "    )", "",
           "    /** Topocentric rows (Los Angeles for C/2023 A3, Sydney for Halley, Mauna Kea for 12P). */",
           "    val topocentricRows: List<TopocentricRow> = listOf("]
    for key, t in topo.items():
        lon, lat, alt = t["site"]
        for jd, r in zip(sorted(t["jds"]), t["rows"]):
            out.append(f"        TopocentricRow(\"{TOPO_CASE[key]}\", {lat!r}, {lon!r}, {alt * 1000!r}, {jd!r}, {float(r['R.A.__(a-app)'])!r}, {float(r['DEC___(a-app)'])!r}, {float(r['Azimuth_(a-app)'])!r}, {float(r['Elevation_(a-app)'])!r}),")
    out.append("    )")
    return "\n".join(out) + "\n"

def swift_topo():
    out = ["", "    /// A topocentric Horizons row: site (CENTER=coord@399, geodetic), UT Julian Day, apparent RA/DEC and airless azimuth/elevation (QUANTITIES 2,4).",
           "    struct TopocentricRow {",
           "        let caseKey: String",
           "        let latitude: Double",
           "        let longitude: Double",
           "        let elevationMeters: Double",
           "        let julianDayUT: Double",
           "        let raApparent: Double",
           "        let decApparent: Double",
           "        let azimuth: Double",
           "        let elevation: Double",
           "    }", "",
           "    /// Topocentric rows (Los Angeles for C/2023 A3, Sydney for Halley, Mauna Kea for 12P).",
           "    static let topocentricRows: [TopocentricRow] = ["]
    for key, t in topo.items():
        lon, lat, alt = t["site"]
        for jd, r in zip(sorted(t["jds"]), t["rows"]):
            out.append(f"        TopocentricRow(caseKey: \"{TOPO_CASE[key]}\", latitude: {lat!r}, longitude: {lon!r}, elevationMeters: {alt * 1000!r}, julianDayUT: {jd!r}, raApparent: {float(r['R.A.__(a-app)'])!r}, decApparent: {float(r['DEC___(a-app)'])!r}, azimuth: {float(r['Azimuth_(a-app)'])!r}, elevation: {float(r['Elevation_(a-app)'])!r}),")
    out.append("    ]")
    return "\n".join(out) + "\n"

def kotlin():
    out = []
    out.append("""package net.kuecker.lodestar.kit.comets

/**
 * Reference ephemerides of JPL Horizons (https://ssd.jpl.nasa.gov/api/horizons.api, queried 2026-10-18; DE441 planets,
 * JPL small-body solutions with N-body integration). For each target the osculating heliocentric elements at one epoch
 * (EPHEM_TYPE=ELEMENTS, CENTER=500@10, REF_PLANE=ECLIPTIC, TIME_TYPE=TDB: EC, QR, IN, OM, W, Tp) and a geocentric
 * observer table at days after that epoch (EPHEM_TYPE=OBSERVER, CENTER=500@399, TLIST in UT, QUANTITIES 1,2,9,19,20,23,24,27):
 * astrometric and apparent right ascension and declination, T-mag/N-mag (comets) or APmag (asteroids), r, delta, S-O-T,
 * S-T-O and PsAng. Generated by a script from the raw answers; the numbers are Horizons' own digits.
 */
internal object CometsHorizonsData {
    /** One line of an observer table; angles in degrees, distances in AU. */
    class Row(
        val offsetDays: Double,
        val raAstrometric: Double,
        val decAstrometric: Double,
        val raApparent: Double,
        val decApparent: Double,
        val magnitude: Double,
        val nuclearMagnitude: Double?,
        val sunDistance: Double,
        val earthDistance: Double,
        val elongation: Double,
        val phaseAngle: Double,
        val tailPositionAngle: Double,
    )

    /** A target: the elements at [epochTDB] (Julian Day, TDB), its magnitude parameters and the table. */
    class Case(
        val title: String,
        val source: String,
        val epochTDB: Double,
        val eccentricity: Double,
        val perihelionDistance: Double,
        val inclination: Double,
        val ascendingNode: Double,
        val argumentOfPerihelion: Double,
        val perihelionTimeTDB: Double,
        val absoluteMagnitude: Double,
        val slope: Double,
        val nuclearMagnitude: Double?,
        val nuclearSlope: Double?,
        val nuclearPhaseCoefficient: Double,
        val rows: List<Row>,
    )
""")
    for key, c in rows_out.items():
        p = c["phys"]
        if c["meta"]["kind"] == "comet":
            h = num(p["M1"]); g = num(p["k1"]); m2 = num(p.get("M2")); k2 = num(p.get("k2")); pc = num(p.get("PHCOF")) or 0.0
        else:
            h = num(p["H"]); g = num(p["G"]); m2 = None; k2 = None; pc = 0.0
        out.append(f"    /** {c['meta']['title']}; {c['meta']['horizons']}. */")
        out.append(f"    val {key}: Case = Case(")
        out.append(f"        title = \"{c['meta']['title']}\",")
        out.append(f"        source = \"{c['meta']['horizons']}\",")
        out.append(f"        epochTDB = {lit(c['epoch'])},")
        out.append(f"        eccentricity = {lit(c['ec'])},")
        out.append(f"        perihelionDistance = {lit(c['qr'])},")
        out.append(f"        inclination = {lit(c['inc'])},")
        out.append(f"        ascendingNode = {lit(c['om'])},")
        out.append(f"        argumentOfPerihelion = {lit(c['w'])},")
        out.append(f"        perihelionTimeTDB = {lit(c['tp'])},")
        out.append(f"        absoluteMagnitude = {lit(h)},")
        out.append(f"        slope = {lit(g)},")
        out.append(f"        nuclearMagnitude = {lit(m2)},")
        out.append(f"        nuclearSlope = {lit(k2)},")
        out.append(f"        nuclearPhaseCoefficient = {lit(pc)},")
        out.append("        rows = listOf(")
        for r in c["rows"]:
            out.append("            Row(" + ", ".join(lit(r[k]) for k in ["offset","ra","dec","raApp","decApp","mag","nuc","r","delta","elong","phase","psang"]) + "),")
        out.append("        ),")
        out.append("    )")
        out.append("")
    out.append("    /** Every case. */")
    out.append("    val cases: List<Case> = listOf(" + ", ".join(list(rows_out.keys())) + ")")
    out.append(kotlin_topo())
    out.append("}")
    return "\n".join(out) + "\n"

def swift():
    out = []
    out.append("""import Foundation

/// Reference ephemerides of JPL Horizons (https://ssd.jpl.nasa.gov/api/horizons.api, queried 2026-10-18; DE441 planets,
/// JPL small-body solutions with N-body integration). For each target the osculating heliocentric elements at one epoch
/// (EPHEM_TYPE=ELEMENTS, CENTER=500@10, REF_PLANE=ECLIPTIC, TIME_TYPE=TDB: EC, QR, IN, OM, W, Tp) and a geocentric
/// observer table at days after that epoch (EPHEM_TYPE=OBSERVER, CENTER=500@399, TLIST in UT, QUANTITIES 1,2,9,19,20,23,24,27):
/// astrometric and apparent right ascension and declination, T-mag/N-mag (comets) or APmag (asteroids), r, delta, S-O-T,
/// S-T-O and PsAng. Generated by a script from the raw answers; the numbers are Horizons' own digits.
enum CometsHorizonsData {
    /// One line of an observer table; angles in degrees, distances in AU.
    struct Row {
        let offsetDays: Double
        let raAstrometric: Double
        let decAstrometric: Double
        let raApparent: Double
        let decApparent: Double
        let magnitude: Double
        let nuclearMagnitude: Double?
        let sunDistance: Double
        let earthDistance: Double
        let elongation: Double
        let phaseAngle: Double
        let tailPositionAngle: Double
    }

    /// A target: the elements at `epochTDB` (Julian Day, TDB), its magnitude parameters and the table.
    struct Case {
        let title: String
        let source: String
        let epochTDB: Double
        let eccentricity: Double
        let perihelionDistance: Double
        let inclination: Double
        let ascendingNode: Double
        let argumentOfPerihelion: Double
        let perihelionTimeTDB: Double
        let absoluteMagnitude: Double
        let slope: Double
        let nuclearMagnitude: Double?
        let nuclearSlope: Double?
        let nuclearPhaseCoefficient: Double
        let rows: [Row]
    }
""")
    for key, c in rows_out.items():
        p = c["phys"]
        if c["meta"]["kind"] == "comet":
            h = num(p["M1"]); g = num(p["k1"]); m2 = num(p.get("M2")); k2 = num(p.get("k2")); pc = num(p.get("PHCOF")) or 0.0
        else:
            h = num(p["H"]); g = num(p["G"]); m2 = None; k2 = None; pc = 0.0
        sl = lambda x: "nil" if x is None else repr(float(x))
        out.append(f"    /// {c['meta']['title']}; {c['meta']['horizons']}.")
        out.append(f"    static let {key} = Case(")
        out.append(f"        title: \"{c['meta']['title']}\",")
        out.append(f"        source: \"{c['meta']['horizons']}\",")
        out.append(f"        epochTDB: {sl(c['epoch'])},")
        out.append(f"        eccentricity: {sl(c['ec'])},")
        out.append(f"        perihelionDistance: {sl(c['qr'])},")
        out.append(f"        inclination: {sl(c['inc'])},")
        out.append(f"        ascendingNode: {sl(c['om'])},")
        out.append(f"        argumentOfPerihelion: {sl(c['w'])},")
        out.append(f"        perihelionTimeTDB: {sl(c['tp'])},")
        out.append(f"        absoluteMagnitude: {sl(h)},")
        out.append(f"        slope: {sl(g)},")
        out.append(f"        nuclearMagnitude: {sl(m2)},")
        out.append(f"        nuclearSlope: {sl(k2)},")
        out.append(f"        nuclearPhaseCoefficient: {sl(pc)},")
        out.append("        rows: [")
        for r in c["rows"]:
            out.append("            Row(" + ", ".join(f"{n}: {sl(r[k])}" for n, k in [("offsetDays","offset"),("raAstrometric","ra"),("decAstrometric","dec"),("raApparent","raApp"),("decApparent","decApp"),("magnitude","mag"),("nuclearMagnitude","nuc"),("sunDistance","r"),("earthDistance","delta"),("elongation","elong"),("phaseAngle","phase"),("tailPositionAngle","psang")]) + "),")
        out.append("        ]")
        out.append("    )")
        out.append("")
    out.append("    /// Every case.")
    out.append("    static let cases: [Case] = [" + ", ".join(list(rows_out.keys())) + "]")
    out.append(swift_topo())
    out.append("}")
    return "\n".join(out) + "\n"

open("CometsHorizonsData.kt", "w").write(kotlin())
open("CometsHorizonsData.swift", "w").write(swift())
print(kotlin()[:200])
