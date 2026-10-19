"""Writes CometsKeplerData.kt/.swift: classical-anomaly Kepler solutions at 60 digits with mpmath (pip install mpmath). Run with `python3 -I`."""
import mpmath as mp
mp.mp.dps = 60
k = mp.mpf("0.01720209895")

def bisect(f, lo, hi, n=260):
    flo = f(lo)
    for _ in range(n):
        mid = (lo + hi) / 2
        fm = f(mid)
        if (fm > 0) == (flo > 0):
            lo, flo = mid, fm
        else:
            hi = mid
    return (lo + hi) / 2

def position(q, e, days):
    q = mp.mpf(q); e = mp.mpf(e); dt = mp.mpf(days)
    sign = 1 if dt >= 0 else -1
    dt = abs(dt)
    if e < 1:
        a = q / (1 - e)
        n = k / a ** mp.mpf("1.5")
        M = n * dt
        twopi = 2 * mp.pi
        M = M - twopi * mp.floor(M / twopi)
        if M > mp.pi:
            M = twopi - M
            flip = -1
        else:
            flip = 1
        E = bisect(lambda E: E - e * mp.sin(E) - M, mp.mpf(0), mp.pi)
        x = a * (mp.cos(E) - e)
        y = a * mp.sqrt(1 - e * e) * mp.sin(E)
        # M was folded into [0, pi]; the sign of y follows the mean anomaly's sign of the original (reduced) M
        n_total = n * dt
        reduced = n_total - twopi * mp.floor(n_total / twopi)
        y_sign = 1 if reduced <= mp.pi else -1
        y = abs(y) * y_sign
    elif e == 1:
        w = k * dt / mp.sqrt(2 * q ** 3)
        s = bisect(lambda s: s + s ** 3 / 3 - w, mp.mpf(0), mp.mpf(10) ** 12)
        x = q * (1 - s * s)
        y = 2 * q * s
    else:
        a = q / (1 - e)  # negative
        aa = -a
        n = k / aa ** mp.mpf("1.5")
        M = n * dt
        H = bisect(lambda H: e * mp.sinh(H) - H - M, mp.mpf(0), mp.mpf(80))
        x = aa * (e - mp.cosh(H))
        y = aa * mp.sqrt(e * e - 1) * mp.sinh(H)
    y = y * sign
    r = mp.sqrt(x * x + y * y)
    return float(x), float(y), float(r)

E_VALUES = ["0", "0.0167", "0.2056", "0.5", "0.9", "0.967", "0.99", "0.9999", "0.999999999", "1", "1.0000001", "1.001", "1.5", "3.346", "6.14", "50"]
Q_VALUES = ["0.5", "1.5", "3.0"]
DT_VALUES = [0.5, -7.0, 60.0, -250.0, 2500.0, 30000.0]
cases = []
for i, e in enumerate(E_VALUES):
    for j, dt in enumerate(DT_VALUES):
        q = Q_VALUES[(i + j) % 3]
        # hyperbolic/parabolic orbits are limited to 50,000 days; elliptic ones reduce mod period
        x, y, r = position(q, e, dt)
        cases.append((float(q), float(e), dt, x, y, r))

def kt():
    o = ["package net.kuecker.lodestar.kit.comets", "",
         "/**",
         " * Reference two-body positions computed with mpmath at 60 digits by classical anomalies, independent of the universal-variable",
         " * solver under test: the eccentric anomaly E from `E - e sin E = M` (e < 1), Barker's equation `s + s^3/3 = k dt / sqrt(2 q^3)` (e = 1)",
         " * or the hyperbolic anomaly H from `e sinh H - H = M` (e > 1), with k = 0.01720209895. Meeus, Astronomical Algorithms, ch. 30, 34",
         " * and 35 give the same equations. `days` is the time since perihelion; x points to perihelion, y 90 degrees ahead in the orbit.",
         " */",
         "internal object CometsKeplerData {",
         "    /** A conic with perihelion distance [q] (AU) and eccentricity [e], and the position [days] after perihelion. */",
         "    class Case(val q: Double, val e: Double, val days: Double, val x: Double, val y: Double, val r: Double)", "",
         "    /** 96 cases: 16 eccentricities from 0 to 50, six times from -250 to 30000 days. */",
         "    val cases: List<Case> = listOf("]
    for c in cases:
        o.append("        Case(" + ", ".join(repr(v) for v in c) + "),")
    o += ["    )", "}"]
    return "\n".join(o) + "\n"

def sw():
    o = ["import Foundation", "",
         "/// Reference two-body positions computed with mpmath at 60 digits by classical anomalies, independent of the universal-variable",
         "/// solver under test: the eccentric anomaly E from `E - e sin E = M` (e < 1), Barker's equation `s + s^3/3 = k dt / sqrt(2 q^3)` (e = 1)",
         "/// or the hyperbolic anomaly H from `e sinh H - H = M` (e > 1), with k = 0.01720209895. Meeus, Astronomical Algorithms, ch. 30, 34",
         "/// and 35 give the same equations. `days` is the time since perihelion; x points to perihelion, y 90 degrees ahead in the orbit.",
         "enum CometsKeplerData {",
         "    /// A conic with perihelion distance `q` (AU) and eccentricity `e`, and the position `days` after perihelion.",
         "    struct Case {", "        let q: Double", "        let e: Double", "        let days: Double", "        let x: Double", "        let y: Double", "        let r: Double", "    }", "",
         "    /// 96 cases: 16 eccentricities from 0 to 50, six times from -250 to 30000 days.",
         "    static let cases: [Case] = ["]
    for c in cases:
        o.append("        Case(q: %r, e: %r, days: %r, x: %r, y: %r, r: %r)," % c)
    o += ["    ]", "}"]
    return "\n".join(o) + "\n"

open("CometsKeplerData.kt", "w").write(kt())
open("CometsKeplerData.swift", "w").write(sw())
print(len(cases))
