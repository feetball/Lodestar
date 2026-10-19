"""Fetches the topocentric Horizons rows of the comets tests (topo.json). Run with `python3 -I`, from the directory of fetch_refs.py."""
import json
from fetch_refs import horizons

def topo(command, jds_ut, lon, lat, alt_km):
    p = dict(format="json", COMMAND=f"'{command}'", OBJ_DATA="'NO'", MAKE_EPHEM="'YES'", EPHEM_TYPE="'OBSERVER'",
             CENTER="'coord@399'", COORD_TYPE="'GEODETIC'", SITE_COORD=f"'{lon},{lat},{alt_km}'",
             TLIST_TYPE="'JD'", TIME_TYPE="'UT'", TLIST="'" + " ".join(repr(j) for j in jds_ut) + "'",
             QUANTITIES="'1,2,4'", ANG_FORMAT="'DEG'", CSV_FORMAT="'YES'", EXTRA_PREC="'YES'", REF_SYSTEM="'ICRF'",
             APPARENT="'AIRLESS'", TIME_DIGITS="'FRACSEC'")
    return horizons(p)

def csv_table(text):
    lines = text.splitlines()
    soe = next(i for i, l in enumerate(lines) if l.startswith("$$SOE"))
    eoe = next(i for i, l in enumerate(lines) if l.startswith("$$EOE"))
    h = soe - 1
    while lines[h].startswith("*"):
        h -= 1
    header = [c.strip() for c in lines[h].split(",")]
    return header, [dict(zip(header, [c.strip() for c in l.split(",")])) for l in lines[soe + 1:eoe]]

out = {}
for key, cmd, jds, site in [
    ("c2023a3_la", "DES=C/2023 A3;CAP;", [2460595.5 + 0.1, 2460603.5 + 0.1], (-118.2437, 34.0522, 0.09)),
    ("halley_sydney", "90000030", [2446470.5 + 60 + 0.4, 2446470.5 + 30 + 0.4], (151.2093, -33.8688, 0.05)),
    ("p12_hawaii", "DES=12P;CAP;", [2460410.5 + 11 + 0.3, 2460410.5 + 25 + 0.3], (-155.4681, 19.8207, 4.2)),
]:
    header, rows = csv_table(topo(cmd, jds, *site))
    out[key] = dict(site=site, jds=jds, header=header, rows=rows)
json.dump(out, open("topo.json", "w"), indent=1)
