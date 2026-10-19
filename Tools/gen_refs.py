"""Fetches the Horizons elements and observer tables of the comets tests (refs.json and hz_*.txt); then run gen_ref_sources.py.
Run with `python3 -I` from this directory."""
import json, os, sys, re
# `python3 -I` leaves the script's directory out of sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_refs import horizons

TARGETS = [
    # key, command, epoch JD TDB, offsets (days from epoch, applied to JD UT)
    ("c2023a3", "DES=C/2023 A3;CAP;", 2460595.5, [-7, 0, 8, 15]),
    ("p12", "DES=12P;CAP;", 2460410.5, [-20, 0, 11, 25]),
    ("halley1986", "90000030", 2446470.5, [-30, 0, 30, 60]),
    ("vesta", "DES=20000004;", 2461200.5, [0, 30, 120]),
    ("ceres", "DES=20000001;", 2461200.5, [0, 30, 120]),
]

def elements(command, jd_tdb):
    p = dict(format="json", COMMAND=f"'{command}'", OBJ_DATA="'YES'", MAKE_EPHEM="'YES'", EPHEM_TYPE="'ELEMENTS'",
             CENTER="'500@10'", REF_PLANE="'ECLIPTIC'", REF_SYSTEM="'ICRF'", OUT_UNITS="'AU-D'",
             TLIST_TYPE="'JD'", TIME_TYPE="'TDB'", TLIST=f"'{jd_tdb}'", CSV_FORMAT="'YES'")
    return horizons(p)

def observer(command, jds_ut):
    p = dict(format="json", COMMAND=f"'{command}'", OBJ_DATA="'YES'", MAKE_EPHEM="'YES'", EPHEM_TYPE="'OBSERVER'",
             CENTER="'500@399'", TLIST_TYPE="'JD'", TIME_TYPE="'UT'", TLIST="'" + " ".join(repr(j) for j in jds_ut) + "'",
             QUANTITIES="'1,2,9,19,20,23,24,27'", ANG_FORMAT="'DEG'", CSV_FORMAT="'YES'", EXTRA_PREC="'YES'",
             RANGE_UNITS="'AU'", TIME_DIGITS="'FRACSEC'")
    return horizons(p)

def csv_table(text):
    lines = text.splitlines()
    soe = next(i for i, l in enumerate(lines) if l.startswith("$$SOE"))
    eoe = next(i for i, l in enumerate(lines) if l.startswith("$$EOE"))
    # header is the nearest line with commas before the asterisks line preceding $$SOE
    h = soe - 1
    while lines[h].startswith("*"): h -= 1
    header = [c.strip() for c in lines[h].split(",")]
    rows = []
    for l in lines[soe + 1:eoe]:
        cells = [c.strip() for c in l.split(",")]
        rows.append(dict(zip(header, cells)))
    return header, rows

out = {}
for key, cmd, ep, offs in TARGETS:
    et = elements(cmd, ep)
    header_e, rows_e = csv_table(et)
    ot = observer(cmd, [ep + o for o in offs])
    header_o, rows_o = csv_table(ot)
    phys = re.findall(r"(M1|M2|k1|k2|H|G|PHCOF)=\s*([-0-9.na]+)", et.split("Initial")[0])
    out[key] = dict(command=cmd, epoch_tdb=ep, offsets=offs, physical=phys, elements=rows_e[0], observer=rows_o,
                    header_o=header_o, soln=[l for l in et.splitlines() if "Soln" in l or "Rec #" in l][:2])
    open(f"hz_{key}_elements.txt", "w").write(et)
    open(f"hz_{key}_observer.txt", "w").write(ot)
json.dump(out, open("refs.json", "w"), indent=1)
for k, v in out.items():
    print(k, v["soln"], v["physical"])
    print("  ", v["header_o"])
    for r in v["observer"]: print("  ", r)
    print("  ", {a: b for a, b in v["elements"].items() if a in ("EC","QR","IN","OM","W","Tp","JDTDB")})
