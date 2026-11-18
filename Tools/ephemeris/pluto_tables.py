"""Meeus (Astronomical Algorithms, 2nd ed., 1998) chapter 37, "Pluto": Table 37.A and the constants of the series.

Pluto's heliocentric longitude l, latitude b (degrees) and radius vector r (AU), referred to the mean equinox and
ecliptic of J2000.0, are valid from 1885 to 2099 (Meeus gives the errors as 0.07" in l, 0.02" in b and 0.000006 AU
in r with respect to the numerical integration they were fitted to). With T in Julian centuries of TT since J2000.0,

    J = 34.35 + 3034.9057 T,   S = 50.08 + 1222.1138 T,   P = 238.96 + 144.96 T        (degrees)
    alpha_n = i_n J + j_n S + k_n P
    l = 238.958116 + 144.96 T + 1e-6 * sum_n (A_n sin alpha_n + B_n cos alpha_n)        (degrees)
    b = -3.908239              + 1e-6 * sum_n (A_n sin alpha_n + B_n cos alpha_n)        (degrees)
    r = 40.7241346             + 1e-7 * sum_n (A_n sin alpha_n + B_n cos alpha_n)        (AU)

with the coefficients of l and b in units of 1e-6 degree and those of r in units of 1e-7 AU, as printed in the book.

TABLE rows are (i, j, k, lon_A, lon_B, lat_A, lat_B, rad_A, rad_B): 43 rows, in the book's order. The numbers were
transcribed from the open-source implementations below (fetched 2026-11-18 with curl; the URLs name the commit that
last changed the file, and the SHA-256 is that of the downloaded file), parsed with this repository's own script
(not by running their code) and compared row by row, digit by digit, on integers (degrees and AU scaled by 1e6 and 1e7):

- soniakeys/meeus, Go, MIT:            all 43 rows (Table 37.A) and the constants   [reference of the comparison]
- commenthol/astronomia, JavaScript:   identical to the Go file in every digit (it is a port of it, so not independent)
- architest/pymeeus, Python, LGPL-3:   identical to the Go file in every digit (typed from the book, independent)
- saurvs/astro-rust, Rust, MIT:        identical to the Go file in every digit (typed from the book, independent)
- libnova, C, LGPL-2+:                 DIFFERS in three digits; the four others agree with each other, so they win:
      row 25 (i, j, k = 1, 1, -3)  longitude B:  -29 (four sources)  but  -20 (libnova)
      row 37 (i, j, k = 2, 0, 0)   longitude B:  -24 (four sources)  but  +24 (libnova)
      row 43 (i, j, k = 3, 0, 0)   radius B:      3  (four sources)  but    2 (libnova)
  (libnova is kept only to document that it carries these transcription errors; none of its numbers are used.)

The constants J, S, P, the mean l (238.958116 + 144.96 T), b (-3.908239) and r (40.7241346) are identical in all five.
Example 37.a (1992 October 13.0 TT = JDE 2448908.5) is stated as l = 232.74071 deg, b = +14.58782 deg, r = 29.711111 AU
by pymeeus (doctest), soniakeys/meeus (Go example) and commenthol/astronomia (test); pymeeus and astronomia add that
the astrometric place is 15h 31m 43.7s (pymeeus) or 43.8s (astronomia), declination -4 deg 27' 29".
"""

# (name, URL at the commit that last changed the file, SHA-256 of the file)
SOURCES = [
    ("soniakeys/meeus v3/pluto/pluto.go (Go, MIT)",
     "https://raw.githubusercontent.com/soniakeys/meeus/c7f0dba3129809c96df09320f64f068e0430ba9d/v3/pluto/pluto.go",
     "36fe0360e04865fd886c94571b5c69fc03ec3c8022d66bc46abdd706c40bb2ee"),
    ("commenthol/astronomia src/pluto.js (JavaScript, MIT)",
     "https://raw.githubusercontent.com/commenthol/astronomia/62f5ff44090a5ddf31e960122c95e1a013b3cfaa/src/pluto.js",
     "2dd8a85b07467f679175a41f3c98c074bb282e5e15a3ee22a1016c71676e3983"),
    ("architest/pymeeus pymeeus/Pluto.py (Python, LGPL-3)",
     "https://raw.githubusercontent.com/architest/pymeeus/f6fb72d1124ad107a3a406d8a126881ef6660be8/pymeeus/Pluto.py",
     "9a407bf676816845319340110b24b5bd693f350e748b7e3ddb3766985917a3cd"),
    ("saurvs/astro-rust src/pluto.rs (Rust, MIT)",
     "https://raw.githubusercontent.com/saurvs/astro-rust/78a35745f8423f891bc1b4e138e3b40215cd8640/src/pluto.rs",
     "e559c40c64b3c6fc3e643d1847e5bae7870bc78e638da1283cf6f7ac39257e5c"),
    ("libnova src/pluto.c (C, LGPL-2+; three transcription errors, not used)",
     "https://sourceforge.net/p/libnova/libnova/ci/655bcd1aec9da10bdb56e6499e2639fa3a953695/tree/src/pluto.c?format=raw",
     "29dc4d6bd858e5f2a95b0f7479d85bd7f4277d9a1cc407f912aa3e1f32be3ae6"),
]

# Mean arguments in degrees: value at J2000.0 and rate per Julian century.
J_MEAN = (34.35, 3034.9057)
S_MEAN = (50.08, 1222.1138)
P_MEAN = (238.96, 144.96)

# Mean heliocentric longitude (degrees; value at J2000.0 and rate per Julian century), latitude (degrees) and
# radius (AU) that the periodic terms are added to.
LONGITUDE_MEAN = (238.958116, 144.96)
LATITUDE_MEAN = -3.908239
RADIUS_MEAN = 40.7241346

# Example 37.a: 1992 October 13.0 TT, JDE 2448908.5.
EXAMPLE_37A_JDE = 2448908.5
EXAMPLE_37A_LONGITUDE = 232.74071
EXAMPLE_37A_LATITUDE = 14.58782
EXAMPLE_37A_RADIUS = 29.711111

# Table 37.A rows: (i, j, k, lon_A, lon_B, lat_A, lat_B, rad_A, rad_B).
TABLE = [
    (0, 0, 1, -19799805, 19850055, -5452852, -14974862, 66865439, 68951812),
    (0, 0, 2, 897144, -4954829, 3527812, 1672790, -11827535, -332538),
    (0, 0, 3, 611149, 1211027, -1050748, 327647, 1593179, -1438890),
    (0, 0, 4, -341243, -189585, 178690, -292153, -18444, 483220),
    (0, 0, 5, 129287, -34992, 18650, 100340, -65977, -85431),
    (0, 0, 6, -38164, 30893, -30697, -25823, 31174, -6032),
    (0, 1, -1, 20442, -9987, 4878, 11248, -5794, 22161),
    (0, 1, 0, -4063, -5071, 226, -64, 4601, 4032),
    (0, 1, 1, -6016, -3336, 2030, -836, -1729, 234),
    (0, 1, 2, -3956, 3039, 69, -604, -415, 702),
    (0, 1, 3, -667, 3572, -247, -567, 239, 723),
    (0, 2, -2, 1276, 501, -57, 1, 67, -67),
    (0, 2, -1, 1152, -917, -122, 175, 1034, -451),
    (0, 2, 0, 630, -1277, -49, -164, -129, 504),
    (1, -1, 0, 2571, -459, -197, 199, 480, -231),
    (1, -1, 1, 899, -1449, -25, 217, 2, -441),
    (1, 0, -3, -1016, 1043, 589, -248, -3359, 265),
    (1, 0, -2, -2343, -1012, -269, 711, 7856, -7832),
    (1, 0, -1, 7042, 788, 185, 193, 36, 45763),
    (1, 0, 0, 1199, -338, 315, 807, 8663, 8547),
    (1, 0, 1, 418, -67, -130, -43, -809, -769),
    (1, 0, 2, 120, -274, 5, 3, 263, -144),
    (1, 0, 3, -60, -159, 2, 17, -126, 32),
    (1, 0, 4, -82, -29, 2, 5, -35, -16),
    (1, 1, -3, -36, -29, 2, 3, -19, -4),
    (1, 1, -2, -40, 7, 3, 1, -15, 8),
    (1, 1, -1, -14, 22, 2, -1, -4, 12),
    (1, 1, 0, 4, 13, 1, -1, 5, 6),
    (1, 1, 1, 5, 2, 0, -1, 3, 1),
    (1, 1, 3, -1, 0, 0, 0, 6, -2),
    (2, 0, -6, 2, 0, 0, -2, 2, 2),
    (2, 0, -5, -4, 5, 2, 2, -2, -2),
    (2, 0, -4, 4, -7, -7, 0, 14, 13),
    (2, 0, -3, 14, 24, 10, -8, -63, 13),
    (2, 0, -2, -49, -34, -3, 20, 136, -236),
    (2, 0, -1, 163, -48, 6, 5, 273, 1065),
    (2, 0, 0, 9, -24, 14, 17, 251, 149),
    (2, 0, 1, -4, 1, -2, 0, -25, -9),
    (2, 0, 2, -3, 1, 0, 0, 9, -2),
    (2, 0, 3, 1, 3, 0, 0, -8, 7),
    (3, 0, -2, -3, -1, 0, 1, 2, -10),
    (3, 0, -1, 5, -3, 0, 0, 19, 35),
    (3, 0, 0, 0, 0, 1, 0, 10, 3),
]
