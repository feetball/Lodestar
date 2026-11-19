"""Generate PlutoTheory.swift and PlutoTheory.kt from Meeus's Pluto series (chapter 37, Table 37.A).

Usage: python -I gen_pluto_theory.py <output PlutoTheory.swift> <output PlutoTheory.kt>

The numbers come from pluto_tables.py (checked against four open-source transcriptions there and against JPL's DE440s by
check_pluto_theory.py). The two outputs carry the same numbers digit for digit: integers for the multipliers and
`repr(float)` for the coefficients (all of them whole numbers in the book's units, so exactly representable). The script
prints the term count and the SHA-256 that `PlutoTheory.tableDigest` of the Kotlin twin must report (the Kotlin test
holds this value; it is the digest of the numbers in the Swift source).
"""
import hashlib
import os
import re
import struct
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pluto_tables as tables  # noqa: E402

WIDTH = 108

INTRO = (
    "Pluto's heliocentric position from the series of Jean Meeus, *Astronomical Algorithms* (2nd ed., 1998), "
    "chapter 37, \"Pluto\": 43 periodic terms in the mean arguments of Jupiter, Saturn and Pluto (Table 37.A), "
    "referred to the mean equinox and ecliptic of J2000.0 and valid from 1885 to 2099 (outside it the error grows "
    "quickly). Pluto has no VSOP87 series; it is a dwarf planet that Lodestar lists with the planets."
)

FORMULAS = (
    "With `T` in Julian centuries of TT since J2000.0 the mean arguments, in degrees, are "
    "`J = 34.35 + 3034.9057 T`, `S = 50.08 + 1222.1138 T` and `P = 238.96 + 144.96 T`, and term `n` has the "
    "argument `α = iJ + jS + kP` for the integers `i`, `j`, `k` of its row of Table 37.A. Then, with its own "
    "pair `A`, `B` per term for each of the three sums,"
)

FORMULA_ITEMS = [
    "`l = 238.958116 + 144.96 T + 10⁻⁶ Σ (A sin α + B cos α)` degrees,",
    "`b = −3.908239 + 10⁻⁶ Σ (A sin α + B cos α)` degrees,",
    "`r = 40.7241346 + 10⁻⁷ Σ (A sin α + B cos α)` AU,",
]

FORMULAS_END = (
    "with `A` and `B` in the book's units, 10⁻⁶ degree for `l` and `b` and 10⁻⁷ AU for `r`. Meeus's example 37.a "
    "(1992 October 13.0 TT) gives l = 232.74071°, b = +14.58782° and r = 29.711111 AU."
)

# Measured by check_pluto_theory.py against the DE440s kernel (SHA-256 c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2).
ACCURACY = (
    "Measured against the Pluto-system barycentre of JPL's DE440s (the Sun to the barycentre, one sample every "
    "10 days; DE440s has no Pluto body, but Pluto's centre is only 0.03–0.08″ from the barycentre at seven dates "
    "compared in JPL Horizons): over 1885–2099 the heliocentric longitude (times cos b) is good to 3.1″ "
    "(rms 1.2″), the latitude to 0.33″ and the radius to 6.5×10⁻⁶ (0.0003 AU). The longitude error is below "
    "1″ from 1885 to 2024 (below 0.6″ from 1900) and grows to 1.2″ by 2049, 2.2″ by 2074 and 3.1″ by 2099, where "
    "the series drifts from DE440s. Outside the span the error grows quickly (up to 1120″ in 1850–1884 and 1400″ in 2100–2149, the "
    "radius by 0.1 %), so the series means something only for 1885–2099. With light-time applied the apparent "
    "geocentric direction differs from DE440s by at most 1.3″ (median 0.4″) and the distance by 4.6×10⁻⁶ over "
    "1950–2049. Being trigonometric, the series stays finite for any date and r stays between 29.6 and 51.8 AU."
)

SOURCES_INTRO = (
    "The coefficients were compared digit by digit (as integers, parsed by script, not by running the code) with "
    "four open-source transcriptions of Table 37.A, which agree in all 43 rows and in the constants. The URLs name "
    "the commit that last changed the file; the SHA-256 is that of the file fetched on 2026-11-18:"
)

SOURCES_END = (
    "A fifth, libnova's `pluto.c`, differs from them in three digits (longitude B of rows 25 and 37, radius B of "
    "row 43) and was not used. The table, the constants and the record of this comparison are in "
    "Tools/ephemeris/pluto_tables.py; Tools/ephemeris/check_pluto_theory.py checks the series against the book's example "
    "and against DE440s."
)


def digest_and_count():
    multipliers = [v for row in tables.TABLE for v in row[0:3]]
    longitude = [float(v) for row in tables.TABLE for v in row[3:5]]
    latitude = [float(v) for row in tables.TABLE for v in row[5:7]]
    radius = [float(v) for row in tables.TABLE for v in row[7:9]]
    return multipliers, longitude, latitude, radius


def table_digest():
    """Same packing as the Kotlin `TableDigest`: an Int is four bytes and a Double eight bytes, both big endian."""
    multipliers, longitude, latitude, radius = digest_and_count()
    digest = hashlib.sha256()
    digest.update(struct.pack(">i", len(multipliers)))
    for value in multipliers:
        digest.update(struct.pack(">i", value))
    for values in (longitude, latitude, radius):
        digest.update(struct.pack(">i", len(values)))
        for value in values:
            digest.update(struct.pack(">d", value))
    return digest.hexdigest()


def literal(value):
    return repr(float(value))


def multiplier_rows(indent):
    pad = " " * indent
    return "\n".join(f"{pad}{i}, {j}, {k}, // {n}" for n, (i, j, k, *_rest) in enumerate(tables.TABLE, 1))


def coefficient_rows(first, indent):
    pad = " " * indent
    return "\n".join(f"{pad}{literal(row[first])}, {literal(row[first + 1])}, // {n}"
                     for n, row in enumerate(tables.TABLE, 1))


def comment_lines(text, prefix):
    return "\n".join((prefix + line).rstrip() for line in text.split("\n"))


def doc_text():
    """The documentation shared by the Swift and Kotlin types, wrapped to `WIDTH` columns."""

    def wrap(text, first="", rest=""):
        # Spaces inside `code spans` do not break lines.
        text = re.sub(r"`[^`]*`", lambda m: m.group(0).replace(" ", "\u00a0"), text)
        return textwrap.fill(text, width=WIDTH, initial_indent=first, subsequent_indent=rest).replace("\u00a0", " ")

    blocks = [wrap(INTRO), "\n".join([wrap(FORMULAS)] + [wrap(item, "- ", "  ") for item in FORMULA_ITEMS]
                                     + [wrap(FORMULAS_END)]), wrap(ACCURACY)]
    sources = [wrap(SOURCES_INTRO)]
    for name, url, sha in tables.SOURCES[:4]:
        sources.append(wrap(f"{name}, SHA-256 {sha}", "- ", "  "))
        sources.append("  " + url)
    sources.append(wrap(SOURCES_END))
    blocks.append("\n".join(sources))
    return "\n\n".join(blocks)


SWIFT = '''import Foundation

extension Ephemeris {
@@DOC@@
    enum PlutoTheory {
        /// The number of periodic terms (43).
        static var termCount: Int { multipliers.count / 3 }

        /// Heliocentric position in AU in the mean equatorial frame of J2000.0 at `julianDayTT`, without light-time.
        static func heliocentricJ2000(julianDayTT: Double) -> Vector3 {
            let t = (julianDayTT - JulianDate.j2000) / JulianDate.daysPerJulianCentury
            let position = heliocentricEcliptic(centuries: t)
            let longitude = AstroMath.radians(position.longitude)
            let latitude = AstroMath.radians(position.latitude)
            let cosLatitude = cos(latitude)
            let ecliptic = Vector3(position.radius * cosLatitude * cos(longitude),
                                   position.radius * cosLatitude * sin(longitude),
                                   position.radius * sin(latitude))
            return eclipticToEquatorialJ2000 * ecliptic
        }

        /// Pluto's heliocentric longitude (degrees, [0, 360)), latitude (degrees) and radius (AU) at `t` Julian
        /// centuries of TT since J2000.0, referred to the mean ecliptic and equinox of J2000.0.
        static func heliocentricEcliptic(centuries t: Double) -> (longitude: Double, latitude: Double, radius: Double) {
            let j = 34.35 + 3034.9057 * t
            let s = 50.08 + 1222.1138 * t
            let p = 238.96 + 144.96 * t

            var sumLongitude = 0.0
            var sumLatitude = 0.0
            var sumRadius = 0.0
            for term in 0..<termCount {
                let multiplierJ = Double(multipliers[3 * term])
                let multiplierS = Double(multipliers[3 * term + 1])
                let multiplierP = Double(multipliers[3 * term + 2])
                let argument = multiplierJ * j + multiplierS * s + multiplierP * p
                let sine = AstroMath.sinDeg(argument)
                let cosine = AstroMath.cosDeg(argument)
                let pair = 2 * term
                sumLongitude += longitudeCoefficients[pair] * sine + longitudeCoefficients[pair + 1] * cosine
                sumLatitude += latitudeCoefficients[pair] * sine + latitudeCoefficients[pair + 1] * cosine
                sumRadius += radiusCoefficients[pair] * sine + radiusCoefficients[pair + 1] * cosine
            }

            // The sums are in millionths of a degree (longitude, latitude) and ten-millionths of an AU (radius).
            return (longitude: AstroMath.normalizeDegrees(238.958116 + 144.96 * t + sumLongitude / 1e6),
                    latitude: -3.908239 + sumLatitude / 1e6,
                    radius: 40.7241346 + sumRadius / 1e7)
        }

        /// Rotation from the J2000 mean ecliptic to the J2000 mean equator.
        private static let eclipticToEquatorialJ2000 = Matrix3.rotationX(AstroMath.radians(Obliquity.j2000))

        /// Table 37.A: the integer multipliers `i`, `j`, `k` of `J`, `S` and `P` in the argument of each term
        /// (three values per term).
        private static let multipliers: [Int] = [
@@MULTIPLIERS@@
        ]

        /// Table 37.A: the coefficients `A` of the sine and `B` of the cosine for the longitude, in 10⁻⁶ degree
        /// (two values per term).
        private static let longitudeCoefficients: [Double] = [
@@LONGITUDE@@
        ]

        /// Table 37.A: the coefficients `A` and `B` for the latitude, in 10⁻⁶ degree (two values per term).
        private static let latitudeCoefficients: [Double] = [
@@LATITUDE@@
        ]

        /// Table 37.A: the coefficients `A` and `B` for the radius, in 10⁻⁷ AU (two values per term).
        private static let radiusCoefficients: [Double] = [
@@RADIUS@@
        ]
    }
}
'''

KOTLIN = '''package net.kuecker.lodestar.kit.ephemeris

import net.kuecker.lodestar.kit.foundation.*
import kotlin.math.cos
import kotlin.math.sin

/**
@@DOC@@
 *
 * In Swift this type is `Ephemeris.PlutoTheory`; Kotlin cannot add nested types from another file, so it is a
 * top-level object of the same package. The numbers are copied digit for digit from the Swift source.
 */
internal object PlutoTheory {
    /**
     * Pluto's heliocentric position referred to the mean ecliptic and equinox of J2000.0.
     *
     * @property longitude Longitude in degrees, [0, 360).
     * @property latitude Latitude in degrees.
     * @property radius Distance from the Sun in AU.
     */
    data class Position(val longitude: Double, val latitude: Double, val radius: Double)

    /** The number of periodic terms (43). Kotlin addition, for tests. */
    val termCount: Int
        get() = multipliers.size / 3

    /**
     * SHA-256 of the series tables as lower-case hex (Kotlin addition, for tests): for the multipliers, then the
     * longitude, latitude and radius coefficients (in this order), the number of values followed by every value, the
     * multipliers as four-byte big-endian integers and the coefficients as the IEEE 754 bits (big endian) of the
     * doubles, so a transcription error in any digit changes it. The test compares it with the digest of the numbers
     * in the Swift source.
     */
    val tableDigest: String
        get() {
            val digest = TableDigest()
            digest.add(multipliers.size)
            for (value in multipliers) digest.add(value)
            for (values in listOf(longitudeCoefficients, latitudeCoefficients, radiusCoefficients)) {
                digest.add(values.size)
                for (value in values) digest.add(value)
            }
            return digest.hex()
        }

    /** Heliocentric position in AU in the mean equatorial frame of J2000.0 at [julianDayTT], without light-time. */
    fun heliocentricJ2000(julianDayTT: Double): Vector3 {
        val t = (julianDayTT - JulianDate.j2000) / JulianDate.daysPerJulianCentury
        val position = heliocentricEcliptic(t)
        val longitude = AstroMath.radians(position.longitude)
        val latitude = AstroMath.radians(position.latitude)
        val cosLatitude = cos(latitude)
        val ecliptic = Vector3(
            position.radius * cosLatitude * cos(longitude),
            position.radius * cosLatitude * sin(longitude),
            position.radius * sin(latitude),
        )
        return eclipticToEquatorialJ2000 * ecliptic
    }

    /**
     * Pluto's heliocentric longitude (degrees, [0, 360)), latitude (degrees) and radius (AU) at [centuries] Julian
     * centuries of TT since J2000.0, referred to the mean ecliptic and equinox of J2000.0.
     *
     * The Swift parameter is `centuries t`; the Kotlin name keeps the label.
     */
    fun heliocentricEcliptic(centuries: Double): Position {
        val t = centuries
        val j = 34.35 + 3034.9057 * t
        val s = 50.08 + 1222.1138 * t
        val p = 238.96 + 144.96 * t

        var sumLongitude = 0.0
        var sumLatitude = 0.0
        var sumRadius = 0.0
        for (term in 0 until termCount) {
            val multiplierJ = multipliers[3 * term].toDouble()
            val multiplierS = multipliers[3 * term + 1].toDouble()
            val multiplierP = multipliers[3 * term + 2].toDouble()
            val argument = multiplierJ * j + multiplierS * s + multiplierP * p
            val sine = AstroMath.sinDeg(argument)
            val cosine = AstroMath.cosDeg(argument)
            val pair = 2 * term
            sumLongitude += longitudeCoefficients[pair] * sine + longitudeCoefficients[pair + 1] * cosine
            sumLatitude += latitudeCoefficients[pair] * sine + latitudeCoefficients[pair + 1] * cosine
            sumRadius += radiusCoefficients[pair] * sine + radiusCoefficients[pair + 1] * cosine
        }

        // The sums are in millionths of a degree (longitude, latitude) and ten-millionths of an AU (radius).
        return Position(
            longitude = AstroMath.normalizeDegrees(238.958116 + 144.96 * t + sumLongitude / 1e6),
            latitude = -3.908239 + sumLatitude / 1e6,
            radius = 40.7241346 + sumRadius / 1e7,
        )
    }

    /** Rotation from the J2000 mean ecliptic to the J2000 mean equator. */
    private val eclipticToEquatorialJ2000: Matrix3 = Matrix3.rotationX(AstroMath.radians(Obliquity.j2000))

    /**
     * Table 37.A: the integer multipliers `i`, `j`, `k` of `J`, `S` and `P` in the argument of each term (three
     * values per term).
     */
    private val multipliers: IntArray = intArrayOf(
@@MULTIPLIERS@@
    )

    /**
     * Table 37.A: the coefficients `A` of the sine and `B` of the cosine for the longitude, in 10⁻⁶ degree (two
     * values per term).
     */
    private val longitudeCoefficients: DoubleArray = doubleArrayOf(
@@LONGITUDE@@
    )

    /** Table 37.A: the coefficients `A` and `B` for the latitude, in 10⁻⁶ degree (two values per term). */
    private val latitudeCoefficients: DoubleArray = doubleArrayOf(
@@LATITUDE@@
    )

    /** Table 37.A: the coefficients `A` and `B` for the radius, in 10⁻⁷ AU (two values per term). */
    private val radiusCoefficients: DoubleArray = doubleArrayOf(
@@RADIUS@@
    )
}
'''


def main():
    swift_path, kotlin_path = sys.argv[1], sys.argv[2]
    assert len(tables.TABLE) == 43
    assert all(len(row) == 9 and all(isinstance(v, int) for v in row) for row in tables.TABLE)
    body = doc_text()
    replacements_swift = {
        "@@DOC@@": comment_lines(body, "    /// "),
        "@@MULTIPLIERS@@": multiplier_rows(12),
        "@@LONGITUDE@@": coefficient_rows(3, 12),
        "@@LATITUDE@@": coefficient_rows(5, 12),
        "@@RADIUS@@": coefficient_rows(7, 12),
    }
    replacements_kotlin = {
        "@@DOC@@": comment_lines(body, " * "),
        "@@MULTIPLIERS@@": multiplier_rows(8),
        "@@LONGITUDE@@": coefficient_rows(3, 8),
        "@@LATITUDE@@": coefficient_rows(5, 8),
        "@@RADIUS@@": coefficient_rows(7, 8),
    }
    for template, replacements, path in ((SWIFT, replacements_swift, swift_path), (KOTLIN, replacements_kotlin, kotlin_path)):
        text = template
        for key, value in replacements.items():
            text = text.replace(key, value)
        assert "@@" not in text
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        print("written", path)
    print("term count:", len(tables.TABLE))
    print("tableDigest:", table_digest())


if __name__ == "__main__":
    main()
