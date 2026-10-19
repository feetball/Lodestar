import json, sys, re, urllib.request, urllib.parse
sys.path.insert(0, ".")

def horizons(params):
    q = urllib.parse.urlencode(params, doseq=True)
    with urllib.request.urlopen("https://ssd.jpl.nasa.gov/api/horizons.api?" + q, timeout=180) as r:
        d = json.loads(r.read().decode())
    return d.get("result", str(d))

def elements(command, jd_tdb):
    p = dict(format="json", COMMAND=f"'{command}'", OBJ_DATA="'YES'", MAKE_EPHEM="'YES'", EPHEM_TYPE="'ELEMENTS'",
             CENTER="'500@10'", REF_PLANE="'ECLIPTIC'", REF_SYSTEM="'ICRF'", OUT_UNITS="'AU-D'",
             TLIST_TYPE="'JD'", TIME_TYPE="'TDB'", TLIST=f"'{jd_tdb}'", CSV_FORMAT="'YES'")
    return horizons(p)

def observer(command, jds_ut, quantities="1,2,9,19,20,23,24,27"):
    p = dict(format="json", COMMAND=f"'{command}'", OBJ_DATA="'YES'", MAKE_EPHEM="'YES'", EPHEM_TYPE="'OBSERVER'",
             CENTER="'500@399'", TLIST_TYPE="'JD'", TIME_TYPE="'UT'", TLIST=[f"'{j}'" for j in jds_ut],
             QUANTITIES=f"'{quantities}'", ANG_FORMAT="'DEG'", CSV_FORMAT="'YES'", EXTRA_PREC="'YES'",
             RANGE_UNITS="'AU'", TIME_DIGITS="'FRACSEC'")
    return horizons(p)

if __name__ == "__main__":
    cmd = sys.argv[1]; jd = float(sys.argv[2]); offs = [float(x) for x in sys.argv[3].split(",")]
    print(elements(cmd, jd))
    print(observer(cmd, [jd + o for o in offs]))
