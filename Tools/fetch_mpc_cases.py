"""Fetches the Horizons rows (2026-10-18 and 2026-11-17, geocentric) that the MPC-line tests compare with (mpc_cases.json)."""
import json, os, re, sys
# `python3 -I` leaves the script's directory out of sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_refs import horizons

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
    h = soe - 1
    while lines[h].startswith("*"):
        h -= 1
    header = [c.strip() for c in lines[h].split(",")]
    return [dict(zip(header, [c.strip() for c in l.split(",")])) for l in lines[soe + 1:eoe]]

out = {}
for key, cmd in [("161P", "DES=161P;CAP;"), ("78P", "DES=78P;CAP;"), ("29P", "DES=29P;CAP;"), ("UN271", "DES=C/2014 UN271;CAP;"),
                 ("E1", "DES=C/2024 E1;CAP;"), ("R2", "DES=P/2026 R2;CAP;")]:
    text = observer(cmd, [2461331.5, 2461361.5])
    head = text.split("Initial")[0] if "Initial" in text else text[:3000]
    out[key] = dict(rows=csv_table(text), phys=re.findall(r"\b(M1|M2|k1|k2|PHCOF)=\s*([-0-9.na]+)", head))
json.dump(out, open("mpc_cases.json", "w"), indent=1)
