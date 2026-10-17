"""Generate Sources/LodestarKit/Ephemeris/PlanetaryTheory.swift from IMCCE's VSOP87B files.

Usage: python -I gen_planetary_theory.py <directory with VSOP87B.*> <output.swift>
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vsop_lib import parse_vsop  # noqa: E402

SPAN_MILLENNIA = 0.3
# (case name, file suffix, semi-major axis in AU used to scale the radius threshold, threshold in rad)
PLANETS = [
    ("earth", "ear", 1.0, 1e-7),
    ("mercury", "mer", 0.387, 1e-6),
    ("venus", "ven", 0.723, 1e-6),
    ("mars", "mar", 1.524, 1e-6),
    ("jupiter", "jup", 5.203, 3e-6),
    ("saturn", "sat", 9.537, 3e-6),
    ("uranus", "ura", 19.19, 3e-6),
    ("neptune", "nep", 30.07, 3e-6),
]

directory, output = sys.argv[1], sys.argv[2]


def selected_series(series, variable, limit):
    """Per power of T (0...max), the terms of one variable whose weighted amplitude reaches the limit."""
    powers = series[variable]
    highest = 0
    kept = {}
    for power, terms in powers.items():
        chosen = [t for t in terms if t[0] * SPAN_MILLENNIA ** power >= limit]
        if chosen:
            kept[power] = chosen
            highest = max(highest, power)
    return [kept.get(power, []) for power in range(highest + 1)]


def literal(value):
    return repr(float(value))


def series_literal(groups, indent):
    pad = " " * indent
    lines = []
    for power, terms in enumerate(groups):
        if not terms:
            lines.append(f"{pad}[],")
            continue
        lines.append(f"{pad}[ // T^{power}: {len(terms)} terms")
        for amplitude, phase, frequency in terms:
            lines.append(f"{pad}    {literal(amplitude)}, {literal(phase)}, {literal(frequency)},")
        lines.append(f"{pad}],")
    return "\n".join(lines)


blocks = []
digests = []
counts = {}
full_total = 0
for name, suffix, semi_major_axis, threshold in PLANETS:
    path = os.path.join(directory, f"VSOP87B.{suffix}")
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    digests.append((f"VSOP87B.{suffix}", digest))
    series = parse_vsop(path)
    full_total += sum(len(terms) for powers in series.values() for terms in powers.values())
    longitude = selected_series(series, 1, threshold)
    latitude = selected_series(series, 2, threshold)
    radius = selected_series(series, 3, threshold * semi_major_axis)
    counts[name] = sum(len(g) for g in longitude + latitude + radius)
    blocks.append(f"""        private static let {name} = Series(
            longitude: [
{series_literal(longitude, 16)}
            ],
            latitude: [
{series_literal(latitude, 16)}
            ],
            radius: [
{series_literal(radius, 16)}
            ])
""")

digest_lines = "\n".join(f"    /// - `{name}`: {digest}" for name, digest in digests)
count_summary = ", ".join(f"{name} {count}" for name, count in counts.items())
total = sum(counts.values())
print("terms:", count_summary, "total", total)

source = f"""import Foundation

extension Ephemeris {{
    /// Heliocentric positions of the Earth and the planets from truncated VSOP87B series.
    ///
    /// VSOP87 (P. Bretagnon & G. Francou, *Astronomy & Astrophysics* 202, 309, 1988) is the
    /// analytical planetary theory of the Bureau des Longitudes, fitted to JPL's DE200. Version B
    /// gives heliocentric spherical coordinates, longitude L, latitude B and radius R, referred to the
    /// dynamical mean ecliptic and equinox of J2000.0. Each coordinate is
    /// `Σₚ Tᵖ · Σ A·cos(φ + ω·T)` with `T` in Julian millennia of TT since J2000.0. The Earth series
    /// is that of the Earth's centre, not of the Earth–Moon barycentre, so the Sun's geocentric
    /// position is its negative.
    ///
    /// The series below keep the terms of the IMCCE files (SHA-256 digests below) whose amplitude
    /// `A`, weighted by {SPAN_MILLENNIA}ᵖ for the power `p` of `T` it multiplies, reaches 10⁻⁷ rad for the Earth,
    /// 10⁻⁶ rad for Mercury, Venus and Mars, and 3×10⁻⁶ rad for Jupiter to Neptune (for the radius, in
    /// AU, the limit is multiplied by the planet's semi-major axis): {total} of {full_total:,} terms.
    /// Against JPL's DE440s over 1850–2050 the apparent geocentric directions are good to 0.3″ (Sun),
    /// 0.6″ (Mercury), 1.5″ (Venus), 5″ (Mars) and 4.5″ (Jupiter to Neptune); the complete series
    /// themselves differ from DE440s by up to 2″ (Neptune).
    ///
    /// Source files (ftp.imcce.fr/pub/ephem/planets/vsop87):
{digest_lines}
    enum PlanetaryTheory {{
        /// The bodies with a series: the Earth and the seven other planets.
        enum Planet {{
            case earth, mercury, venus, mars, jupiter, saturn, uranus, neptune
        }}

        /// Heliocentric position in AU in the mean equatorial frame of J2000.0 at `julianDayTT`.
        static func heliocentricJ2000(_ planet: Planet, julianDayTT: Double) -> Vector3 {{
            let t = (julianDayTT - JulianDate.j2000) / 365_250
            let series = series(for: planet)
            let longitude = sum(series.longitude, at: t)
            let latitude = sum(series.latitude, at: t)
            let radius = sum(series.radius, at: t)
            let cosLatitude = cos(latitude)
            let ecliptic = Vector3(radius * cosLatitude * cos(longitude),
                                   radius * cosLatitude * sin(longitude),
                                   radius * sin(latitude))
            return eclipticToEquatorialJ2000 * ecliptic
        }}

        /// Rotation from the J2000 mean ecliptic to the J2000 mean equator.
        private static let eclipticToEquatorialJ2000 = Matrix3.rotationX(AstroMath.radians(Obliquity.j2000))

        /// Terms of L, B and R grouped by the power of T (index 0, 1, …); each group lists
        /// `amplitude, phase, frequency` triples (amplitude in radians or AU, phase in radians,
        /// frequency in radians per millennium).
        private struct Series {{
            let longitude: [[Double]]
            let latitude: [[Double]]
            let radius: [[Double]]
        }}

        private static func sum(_ groups: [[Double]], at t: Double) -> Double {{
            var total = 0.0
            var power = 1.0
            for terms in groups {{
                var partial = 0.0
                for index in stride(from: 0, to: terms.count, by: 3) {{
                    partial += terms[index] * cos(terms[index + 1] + terms[index + 2] * t)
                }}
                total += partial * power
                power *= t
            }}
            return total
        }}

        private static func series(for planet: Planet) -> Series {{
            switch planet {{
            case .earth: earth
            case .mercury: mercury
            case .venus: venus
            case .mars: mars
            case .jupiter: jupiter
            case .saturn: saturn
            case .uranus: uranus
            case .neptune: neptune
            }}
        }}

{chr(10).join(blocks)}    }}
}}
"""
open(output, "w", encoding="utf-8").write(source)
print("written", output)
