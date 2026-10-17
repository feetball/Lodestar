# Tools

Generators for the data Lodestar ships with. Every script pins its upstream sources and checks
them, so the generated files can be rebuilt byte for byte.

## Catalog data

`build_catalogs.py` builds the four JSON catalogs that `LodestarKit` bundles from open data on
GitHub. It needs Python 3.9 or newer (tested with 3.11) and nothing but the standard library.

```
python3 -I Tools/build_catalogs.py --out LodestarKit/Sources/LodestarKit/Resources \
    --cache Tools/.cache
```

Always run it with `-I` (isolated mode). The first run downloads about 38 MB into `--cache`; later
runs work offline. The cache is disposable and holds one folder per source and commit.

| Flag | Effect |
| --- | --- |
| `--out DIR` | where `stars.json`, `dsos.json`, `constellations.json`, `milkyway.json` go |
| `--cache DIR` | download cache |
| `--lock FILE` | lock file, default `Tools/sources.lock.json` |
| `--check` | build in memory and fail if `--out` differs; writes nothing |
| `--refresh-lock` | resolve each source's ref to its current commit, re-download, re-hash, and rewrite the lock after the build succeeds |
| `--ref KEY=REF` | with `--refresh-lock`: follow another branch or tag for source `hyg`, `openngc` or `d3celestial` |

### Output

| File | Content | Entries | Size |
| --- | --- | --- | --- |
| `stars.json` | stars with V ≤ 6.5 plus every named star | 9,001 | 1.3 MB |
| `dsos.json` | Messier, named and bright NGC/IC objects | 693 | 86 KB |
| `constellations.json` | the 88 IAU constellations | 88 | 25 KB |
| `milkyway.json` | five Milky Way brightness outlines | 185 rings | 39 KB |

All files are UTF-8 JSON with one entry per line. Angles are degrees: right ascension in [0, 360),
declination in [-90, 90], J2000. Numbers are rounded (positions to 6 decimals, magnitudes and
proper motions to 2). Keys with unknown values are omitted. The `generated` date is the date the
lock was created, so the same lock always reproduces the same bytes.

**`stars.json`**: `{"schema":1,"source","license","generated","stars":[...]}`, sorted by magnitude.

| Key | Meaning |
| --- | --- |
| `hip`, `hr`, `hd` | Hipparcos, Harvard Revised (Yale Bright Star) and Henry Draper numbers |
| `hyg` | HYG row id; only on named stars that have neither `hip` nor `hr` |
| `n` | proper name |
| `b` | Bayer designation as Greek letter and superscript digit (`α`, `κ¹`) |
| `f` | Flamsteed number |
| `c` | IAU constellation abbreviation (`UMa`) |
| `ra`, `de` | position at epoch J2000.0 (see "Positions" below) |
| `pa`, `pd` | proper motion in mas/yr; `pa` is μα* = μα·cos δ |
| `m`, `ci` | V magnitude and B−V |
| `sp` | spectral type, at most 12 characters |
| `d` | distance in parsecs, only when known |

**`dsos.json`**: `{"schema":1,"source","license","generated","objects":[...]}`, ordered Messier,
NGC, IC, others.

| Key | Meaning |
| --- | --- |
| `id` | unique and stable: `M31` for Messier objects, otherwise the OpenNGC name without zero padding (`NGC224`, `IC434`, `C41`, `ESO56-115`) |
| `m` | Messier number |
| `ngc`, `ic` | every NGC/IC number of the object, its own first; duplicates are merged (`NGC2239` carries 2244) |
| `names` | common names in display order, acronyms (`LMC`) last |
| `t` | OpenNGC type: `G OCl GCl PN HII EmN RfN Neb SNR DrkN Cl+N *Ass GPair GTrpl GGroup ** * Other` |
| `ra`, `de`, `c` | position and constellation |
| `vm`, `bm` | V and B magnitudes |
| `maj`, `min`, `pa` | size in arcminutes and position angle in degrees |
| `h`, `sb` | galaxy Hubble type and surface brightness |

**`constellations.json`**: `{"schema":1,"source","license","constellations":[...]}` with `abbr`,
`name`, `genitive`, `label` (`[ra, de]`) and `lines`, the stick figure as polylines of `[ra, de]`.
Consecutive vertices are joined by great-circle arcs. Polylines may cross RA 0°/360°, so
interpolate on the sphere, not in RA.

**`milkyway.json`**: `{"schema":1,"source","license","levels":[...]}`. Level 1 is the faint outer
glow, level 5 the bright core. A level has `polygons` (filled rings) and, when present, `holes`
(dark lanes). Draw one path made of both lists with the even-odd rule, or fill `polygons` and
punch out `holes`. Rings are implicitly closed (the first vertex is not repeated). With RA to the
right and Dec up, fills run counter-clockwise and holes clockwise, so the non-zero rule gives the
same picture (mirroring the chart flips both alike). Edges are great-circle arcs, so subdivide long
edges for wide fields of view. The single level-1 band circles the whole sky; it is cut along
RA 180° by a zero-width slit (a seam of collinear vertices that must not be stroked).

### Sources

Each source is pinned to a commit and every file to a sha256 digest in `sources.lock.json`.

| Source | Pinned | License |
| --- | --- | --- |
| [HYG Database v4.1](https://github.com/astronexus/HYG-Database) | `main` @ `c7f7f883fe67` | CC BY-SA 4.0 |
| [OpenNGC](https://github.com/mattiaverga/OpenNGC) | `v20260501` @ `36cb178a0f69` | CC BY-SA 4.0 |
| [d3-celestial](https://github.com/ofrohn/d3-celestial) | `master` @ `7e720a3de062` | BSD-3-Clause |

`stars.json` and `dsos.json` stay CC BY-SA 4.0 as derived data. See [`../ATTRIBUTION.md`](../ATTRIBUTION.md)
for credits and the license texts.

### Selection rules

- **Stars:** every HYG star with V ≤ 6.5 or a proper name, except the Sun. Every entry must carry a
  Hipparcos or Harvard Revised number. Of the 32 selected rows that have neither, 25 are unnamed
  Gliese "B" companions that lie 2–28″ from a Hipparcos star already in the file (Gl 194B, listed
  at V 0.96, is 13″ from Capella); they would only add duplicate stars and are dropped. The other
  7 are named (Wolf 359, Ross 248, EZ Aqr, Ross 686, Kaewkosin, Maru, Onkaria) and keep the HYG
  row id in `hyg`.
- **Positions:** HYG advanced Hipparcos' epoch-1991.25 positions to 2000.0 by adding the proper
  motion in right ascension to RA as if it were a coordinate rate, without the `1/cos δ` factor.
  The error on the sky is μα*·8.75 yr·(1 − cos δ): below 0.1″ for most stars, above 1″ for about
  120, and 18″ for Proxima Centauri and the α Centauri pair. The script adds the missing term to
  the right ascension of every star that has a Hipparcos number (declinations were right). All
  8,969 such stars were compared with Hipparcos positions at J2000.0 from VizieR (catalog I/239):
  before the correction the median difference was 0.03″ and the maximum 17.9″; after it the
  median is 0.01″ and 8,968 stars lie within 0.05″ (α Centauri B, whose HYG proper motion differs
  from Hipparcos', is 4″ off). Stars without a Hipparcos number are left as HYG has them.
- **Deep-sky objects:** all 110 Messier objects; every object with a common name; every other
  object with V ≤ 10.0, or B ≤ 10.5 when V is unknown; and every nebula-type object (`HII EmN RfN
  Neb SNR DrkN Cl+N`) of at least 10′ that has no magnitude at all, because OpenNGC lists none for
  many of the best wide-field targets (Flame Nebula, Pacman, Thor's Helmet, Elephant's Trunk).
  `Dup`, `NonEx` and `Nova` rows are skipped, and so are plain stars (`*`, `**`) unless they are
  Messier objects or named.
- **Names:** OpenNGC's common names with a leading "the" removed, preceded by a small table of
  added names (`SUPPLEMENTARY_NAMES`: Heart Nebula, Pinwheel Galaxy, "LMC", ...). Each entry is
  checked against the object's OpenNGC constellation, so a typo fails the build. "Flame Nebula" is
  removed from IC 434 because it is NGC 2024.
- **Messier 102:** OpenNGC lists M102 as a duplicate of M101. The conventional identification
  with NGC 5866 is used so that the list holds all 110 objects.
- **Constellations:** names and genitives come from an IAU table in the script that d3-celestial is
  checked against. d3-celestial has two errors, corrected in the output: Corona Australis is
  "Corona Austrina / Coronae Austrini" and Crux has the genitive "Crux". Serpens, split in two
  features upstream, is merged into `Ser`.
- **Milky Way:** each ring is simplified to 0.25° (Douglas–Peucker on the sphere, 3 decimals),
  self-crossing source contours are split, and rings are sorted into fills and holes by nesting.
  The source rings are contours, so nesting parity, not their orientation, decides which are
  holes. The result was compared with the source on a 3° grid covering the sphere, five levels
  deep: 24 of 36,000 sample points differ, all within 0.6° of a source outline.

### Validation

A failed check stops the build before any file is written. Checked: finite numbers; right
ascension and declination ranges; unique ids; known object types; constellation abbreviations
against the 88-entry list; five stars (Sirius, Polaris, Proxima Centauri, Rigil Kentaurus,
Barnard's Star) within 0.07″ of their Hipparcos positions; Polaris is HIP 11767; Betelgeuse
named and α; M31 at (10.6848, 41.2690); M42 present; Messier numbers exactly 1–110; the famous
targets (LMC, SMC, Pleiades, Hyades, Double Cluster, ω Cen, 47 Tuc, Carina, North America,
Rosette, Horsehead, Veil, Helix, Lagoon, Orion, Andromeda, Triangulum, Coma cluster, Flame,
Pacman, Elephant's Trunk, Heart, Soul); exactly 88 constellations; `milkyway.json` under 200 KB.

### Security

- Downloads use HTTPS only and refuse redirects that leave TLS. Each URL is
  `raw.githubusercontent.com/<repo>/<full commit sha>/<path>`, which cannot change.
- A file is used only after its sha256 digest and size match the lock. A cached file that does not
  match is downloaded again; a download that does not match is deleted and fails the build.
- Downloaded content is parsed with `csv` and `json` only and is never executed or evaluated.
  Download size is capped and repository paths are validated.
- `--refresh-lock` hashes license and readme files too and warns loudly when upstream terms
  change, so a license change cannot slip in with a data update. Review such a refresh by
  reading the `git diff` of `sources.lock.json`.

### Updating a source

```
python3 -I Tools/build_catalogs.py --out LodestarKit/Sources/LodestarKit/Resources \
    --cache Tools/.cache --refresh-lock [--ref openngc=<tag>]
```

Then review the lock diff, copy the new commit hashes into `ATTRIBUTION.md` (the script warns
when they are missing) and commit the lock together with the regenerated data. OpenNGC is pinned
to a release tag; find newer ones at <https://github.com/mattiaverga/OpenNGC/tags>.

### Known limitations

- The GitHub copy of HYG is an archive frozen at v4.1. Upstream continues on Codeberg
  (<https://codeberg.org/astronexus/hyg>) and is at v4.4, with 34+ further IAU names. It ships
  as `.csv.gz`, so using it needs a new source definition and gzip support.
- The Milky Way outlines descend from Jose R. Vieira's *Milky Way Outline Catalog*, whose own
  license could not be verified; d3-celestial redistributes it under BSD-3-Clause.
- OpenNGC magnitudes are taken as given. Some are implausible (NGC 253 has V 11.1 and B 7.9).
- Three named plain stars come from OpenNGC (`t` is `*`): NGC 1990 is Alnilam and IC 1318 is the
  nebula around Sadr, both also in `stars.json`; NGC 7114 is Schmidt's Nova Cygni.
- HYG v4.1 gives two different stars the name "p Eridani" (HR 486 and HR 487); v4.4 fixed this.
- Constellation stick figures are d3-celestial's, which differ slightly from other traditions.

## Ephemeris theories

`ephemeris/` regenerates the two coefficient files of LodestarKit's Ephemeris module. Both scripts use
only the Python standard library and must be run with `-I`.

```
python3 -I Tools/ephemeris/gen_lunar_theory.py LodestarKit/Sources/LodestarKit/Ephemeris/LunarTheory.swift
python3 -I Tools/ephemeris/gen_planetary_theory.py <dir with VSOP87B.*> \
    LodestarKit/Sources/LodestarKit/Ephemeris/PlanetaryTheory.swift
```

- `LunarTheory.swift` comes from Meeus, *Astronomical Algorithms* (2nd ed.), Tables 47.A and 47.B
  (`meeus_lunar_tables.py`), cross-checked row by row against the MIT-licensed implementations
  `soniakeys/meeus` and `commenthol/astronomia`, and against JPL DE440s by the Swift tests.
- `PlanetaryTheory.swift` is a truncation (1,002 of 35,080 terms) of the VSOP87B series by Bretagnon &
  Francou (A&A 202, 309, 1988). Download the eight `VSOP87B.*` files from
  `ftp.imcce.fr/pub/ephem/planets/vsop87/` (also on CDS VizieR, catalogue VI/81); their SHA-256 digests
  are listed in the header of the generated file, which the script reproduces byte for byte.
