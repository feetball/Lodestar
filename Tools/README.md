# Tools

Generators for the data Lodestar ships with. Every script pins its upstream sources and checks
them, so the generated files can be rebuilt byte for byte.

## Catalog data

`build_catalogs.py` builds the four JSON catalogs that `LodestarKit` bundles from open data on
GitHub and from catalogues distributed by CDS (VizieR). It needs Python 3.9 or newer (tested with
3.11) and nothing but the standard library.

```
python3 -I Tools/build_catalogs.py --out LodestarKit/Sources/LodestarKit/Resources \
    --cache Tools/.cache
```

Always run it with `-I` (isolated mode). The first run downloads about 38 MB into `--cache`; later
runs work offline. The cache is disposable and holds one folder per source and commit (`cds` for
the CDS catalogues, whose files are checked by their sha256 digest alone).

| Flag | Effect |
| --- | --- |
| `--out DIR` | where `stars.json`, `dsos.json`, `constellations.json`, `milkyway.json` go |
| `--cache DIR` | download cache |
| `--lock FILE` | lock file, default `Tools/sources.lock.json` |
| `--check` | build in memory and fail if `--out` differs; writes nothing |
| `--refresh-lock` | resolve each source's ref to its current commit, re-download, re-hash, and rewrite the lock after the build succeeds |
| `--only KEY` | with `--refresh-lock`: refresh just that source (repeatable) and keep the other lock entries and the lock date, so the other outputs stay byte for byte the same |
| `--ref KEY=REF` | with `--refresh-lock`: follow another branch or tag for source `hyg`, `openngc` or `d3celestial` (the CDS sources have no refs) |

### Output

| File | Content | Entries | Size |
| --- | --- | --- | --- |
| `stars.json` | stars with V ≤ 6.5 plus every named star | 9,001 | 1.3 MB |
| `dsos.json` | Messier, Caldwell, named and photographable NGC/IC objects, Sharpless, Barnard and Lynds nebulae, large open clusters | 2,441 | 284 KB |
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
NGC, IC, others (in natural order of the id: `B2` before `B10`, `Sh2-9` before `Sh2-10`).

| Key | Meaning |
| --- | --- |
| `id` | unique and stable: `M31` for Messier objects, the OpenNGC name without zero padding (`NGC224`, `IC434`, `C41`, `ESO56-115`), `Sh2-155` for Sharpless regions, `B33` or `B67a` for Barnard objects, `LDN1622` for Lynds clouds, `Cl69`, `Mel20`, `Tr24`, `St2` for Collinder, Melotte, Trumpler and Stock clusters. Ids of the first release never change |
| `m` | Messier number |
| `ngc`, `ic` | every NGC/IC number of the object, its own first; duplicates are merged (`NGC2239` carries 2244) |
| `cat` | designations in other catalogues, compact: `C20` Caldwell, `Sh2-117` Sharpless 2, `Mel22`, `Cl50`, `Tr37`. Letters (the first upper case, at most six), a number of at most six digits, optionally one more letter; or `Sh2-` and up to four digits. At most 16. Caldwell first, then Sharpless, Melotte, Collinder... |
| `p` | prominence 1 (showpiece) to 4 (obscure), see "Prominence" below. Absent means 3 |
| `names` | common names in display order, acronyms (`LMC`) last |
| `t` | OpenNGC type: `G OCl GCl PN HII EmN RfN Neb SNR DrkN Cl+N *Ass GPair GTrpl GGroup ** * Other` |
| `ra`, `de`, `c` | position and constellation |
| `vm`, `bm` | V and B magnitudes |
| `maj`, `min`, `pa` | size in arcminutes and position angle in degrees. Sharpless regions: the largest extent, `min` equal to it when the catalogue calls the region circular. Barnard: the diameter (some have none). Lynds: the diameter of the circle with the cloud's area |
| `h`, `sb` | galaxy Hubble type and surface brightness |

`cat` and `p` are optional members; schema 1 is unchanged and an older decoder skips them. Sharpless,
Barnard, Lynds and cluster objects have no magnitude (`vm`, `bm`).

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
| [CDS VII/20](https://cdsarc.cds.unistra.fr/ftp/VII/20/): Sharpless, *Catalogue of HII Regions* (ApJS 4, 257, 1959) | file sha256 | CDS terms |
| [CDS VII/220A](https://cdsarc.cds.unistra.fr/ftp/VII/220A/): Barnard, *Catalogue of 349 Dark Objects in the Sky* (1927), machine-readable version by Takahashi & Ohishi and Gray | file sha256 | CDS terms |
| [CDS VII/7A](https://cdsarc.cds.unistra.fr/ftp/VII/7A/): Lynds, *Catalogue of Dark Nebulae* (ApJS 7, 1, 1962) | file sha256 | CDS terms |
| [CDS B/ocl](https://cdsarc.cds.unistra.fr/ftp/B/ocl/): Dias et al., *Optically visible open clusters and candidates*, v3.5 (A&A 389, 871, 2002) | file sha256 | CDS terms |
| [CDS VI/42](https://cdsarc.cds.unistra.fr/ftp/VI/42/): Roman, *Identification of a constellation from a position* (PASP 99, 695, 1987; boundaries of Delporte 1930) | file sha256 | CDS terms |

`stars.json` and `dsos.json` stay CC BY-SA 4.0 as derived data of OpenNGC and HYG. The CDS catalogues
carry no license of their own: CDS lets the data be used freely in a scientific context with the
original authors and publication cited and a VizieR acknowledgement appreciated, and says that
commercial use depends on the origin of the catalogue (<https://cds.unistra.fr/vizier-org/licences_vizier.html>).
All five are decades-old compilations of astronomical facts (positions, sizes, classes). See
[`../ATTRIBUTION.md`](../ATTRIBUTION.md) for credits and the license texts.

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
- **Deep-sky objects from OpenNGC**, two rules. The *first rule* (the first release, 693 objects):
  all 110 Messier objects; every object with a common name; every other object with V ≤ 10.0, or B ≤
  10.5 when V is unknown; and every nebula-type object (`HII EmN RfN Neb SNR DrkN Cl+N`) of at least 10′
  that has no magnitude at all, because OpenNGC lists none for many of the best wide-field targets
  (Flame Nebula, Pacman, Thor's Helmet, Elephant's Trunk). The *extended rule* adds what a photographer
  reaches with a camera lens or a small telescope: V ≤ 11.5 (B ≤ 12.0 when V is unknown), any nebula of at
  least 3′, any open cluster, cluster with nebulosity or association of at least 30′, and every Caldwell
  object. `Dup`, `NonEx` and `Nova` rows are skipped, and so are plain stars (`*`, `**`) unless they are
  Messier objects or named. Together 1,412 OpenNGC objects (719 more than the first rule).
  OpenNGC's cross-references to NGC/IC numbers that are objects of their own are dropped (NGC 7418 and
  NGC 7368 list IC 1459, a galaxy 35′ away).
- **Caldwell:** the 109 Caldwell numbers come from OpenNGC's `Identifiers` column (`C 020`) and from
  the four addendum rows `C009`, `C014`, `C041`, `C099` (Cave Nebula, Double Cluster, Hyades, Coalsack)
  that have no NGC/IC number. Every number must be present exactly once; 25 of them are checked
  against Moore's list (the whole list was compared with the Wikipedia table when this was written). A
  Caldwell object is a designation (`"cat":["C20"]`) of its NGC/IC object.
- **Sharpless 2** (CDS VII/20, 313 regions): all of them. The catalogue gives B1900.0 centers, precessed
  to J2000.0 (IAU 1976 rotation; the catalogue's own accuracy is a few arcminutes, a fraction of the
  region's size) and the largest diameter. 47 regions are objects OpenNGC already lists (Sh2-25 is the
  Lagoon Nebula M 8, Sh2-117 the North America Nebula, Sh2-281 the Orion Nebula, ...): they are not new
  objects but a `cat` entry, from the table `SHARPLESS_IDENTIFICATIONS`, made by comparing positions
  and sizes and reviewed by hand; each must lie within half a region diameter (at least 15′) of the
  object. The other 266 are objects of type `HII`, except `SHARPLESS_TYPES` (Sh2-188, 216, 274, 290 are
  planetary nebulae, Sh2-240 is the supernova remnant Simeis 147). Popular names (`SHARPLESS_NAMES`:
  Flying Bat, Lion, Tulip, Spaghetti, Medusa, Barnard's Loop, ...).
- **Barnard** (CDS VII/220A, 349 objects, the J2000.0 positions of the file, checked against the original
  1875.0 ones): all of them, as dark nebulae with the catalogue's diameter. Barnard 33 is OpenNGC's
  Horsehead and stays that object. Names: Snake (B 72), Pipe (B 78), Ink Spot (B 86), Seahorse (B 150).
- **Lynds** (CDS VII/7A, 1,787 numbered clouds of the 1,791 in the file): the cut keeps the 398 clouds
  that have opacity class 6 (the darkest) or an area of at least one square degree (248 clouds), plus
  named ones (LDN 1622 Boogeyman, LDN 1235 Shark; both are class 6 anyway). B1950.0 centers are
  precessed to J2000.0; the size is the diameter of the circle with the cloud's area. The 1,389 clouds
  left out are mostly faint patches of a few arcminutes.
- **Open clusters** (CDS B/ocl): Collinder, Melotte, Trumpler and Stock clusters between 60′ and 10° across
  (22 of them in the catalogue; Collinder 285, the 23° Ursa Major group, is left out). Those that are
  objects of the catalog already (Melotte 22 = M 45, Melotte 25 = Caldwell 41 = Collinder 50,
  Melotte 111, Trumpler 37 = IC 1396) become designations, 17 are new. Melotte 20 (the Alpha Persei
  Cluster) is the best known. There is no clean licensed source of Abell planetary nebulae with
  magnitudes, so none are included (Sh2-274, the Medusa Nebula = Abell 21, and Sh2-290 = Abell 31 are).
- **Constellations of the new objects** (`c`) come from the IAU boundaries of Delporte as arranged by Roman
  (CDS VI/42): the position is precessed to B1875.0 and looked up in the 357-row table. The build
  checks the method against OpenNGC's own constellation of every NGC/IC object it keeps: no
  disagreement.
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

### Prominence

`p` says how conspicuous a deep-sky object is, from 1 (showpiece) to 4 (obscure), so that sky views can
draw only the prominent ones at wide fields and browse lists can leave out the obscure ones. A smaller
number is more prominent. The thresholds are constants at the top of `build_catalogs.py`, the rules are
`dso_prominence`. Magnitudes are V, else B.

| p | Name | Rule (the first that applies) |
| --- | --- | --- |
| 1 | showpiece | Messier or Caldwell object; one of 26 hand-picked popular targets (`SHOWPIECES`: Horsehead, Flame, Heart, Soul, California, Wizard, Elephant's Trunk, Pelican, Witch Head, Flying Bat, Lion, Boogeyman, ...); brighter than magnitude 4. Plain stars never |
| 2 | prominent | brighter than magnitude 8; named and (brighter than 10 or larger than 30′); a nebula of at least 60′, or a Sharpless region of at least 60′ of brightness class 2 or 3 (also when it is an NGC/IC object); a named dark nebula; a Barnard object of at least 3°; a Dias cluster of at least 2° |
| 3 | notable | selected by the first rule (so nothing that was listed in the first release is unlisted); any other named object; a nebula of at least 10′; a Sharpless region of at least 30′ (10′ in the brightest class); a Barnard object of at least 1°; a Lynds cloud of at least 3°, or class 6 and at least 20′; an open cluster, cluster with nebulosity or association of at least 30′ |
| 4 | obscure | the rest |

Dark nebulae have no magnitude and are rated by name, size and (Lynds) opacity. The bundled data has
253 showpieces, 234 prominent, 508 notable and 1,446 obscure objects. The engines list (`isListed`)
the objects up to 3.

### Validation

A failed check stops the build before any file is written. Checked: finite numbers; right
ascension and declination ranges; unique ids; known object types; constellation abbreviations
against the 88-entry list; five stars (Sirius, Polaris, Proxima Centauri, Rigil Kentaurus,
Barnard's Star) within 0.07″ of their Hipparcos positions; Polaris is HIP 11767; Betelgeuse
named and α; M31 at (10.6848, 41.2690); M42 present; Messier numbers exactly 1–110; the famous
targets (LMC, SMC, Pleiades, Hyades, Double Cluster, ω Cen, 47 Tuc, Carina, North America,
Rosette, Horsehead, Veil, Helix, Lagoon, Orion, Andromeda, Triangulum, Coma cluster, Flame,
Pacman, Elephant's Trunk, Heart, Soul); exactly 88 constellations; `milkyway.json` under 200 KB.
For `dsos.json`: no NGC/IC number or cross designation belongs to two objects; exactly the Caldwell
numbers 1 to 109, the Sharpless regions 1 to 313 and the 349 Barnard objects are present; 25 Caldwell
objects are the NGC/IC objects of Moore's list; named objects (Horsehead, Snake, Boogeyman, Flying Bat,
...) sit in the constellation the tables say; the Medusa Nebula, Abell 31, the Horsehead and the
Boogeyman lie where SIMBAD and the literature put them; every name of the hand-made tables must still
exist and match its constellation; every object has a constellation (the lookup reproduces OpenNGC's);
every Messier and Caldwell object has prominence 1; the file is at most 600 KB.

### Security

- Downloads use HTTPS only and refuse redirects that leave TLS. Each GitHub URL is
  `raw.githubusercontent.com/<repo>/<full commit sha>/<path>`, which cannot change. CDS files have no
  commit; their URLs (`https://cdsarc.cds.unistra.fr/ftp/<catalogue>/<file>`) are only trusted through the
  sha256 digest and size in the lock, so a replaced file fails the build.
- A file is used only after its sha256 digest and size match the lock. A cached file that does not
  match is downloaded again; a download that does not match is deleted and fails the build.
- Downloaded content is parsed with `csv`, `json`, `gzip` and fixed-width slicing only and is never
  executed or evaluated.
  Download size is capped and repository paths are validated.
- `--refresh-lock` hashes license and readme files too and warns loudly when upstream terms
  change, so a license change cannot slip in with a data update. Review such a refresh by
  reading the `git diff` of `sources.lock.json`.

### Updating a source

```
python3 -I Tools/build_catalogs.py --out LodestarKit/Sources/LodestarKit/Resources \
    --cache Tools/.cache --refresh-lock [--ref openngc=<tag>]
```

`--only KEY` (repeatable) refreshes just those sources and keeps the lock date, which is how the CDS
sources were added without touching the others. Then review the lock diff, copy the new commit hashes
and the CDS catalogue numbers into `ATTRIBUTION.md` (the script warns when they are missing) and commit
the lock together with the regenerated data. OpenNGC is pinned
to a release tag; find newer ones at <https://github.com/mattiaverga/OpenNGC/tags>.

### Known limitations

- The GitHub copy of HYG is an archive frozen at v4.1. Upstream continues on Codeberg
  (<https://codeberg.org/astronexus/hyg>) and is at v4.4, with 34+ further IAU names. It ships
  as `.csv.gz`, so using it needs a new source definition and gzip support.
- The Milky Way outlines descend from Jose R. Vieira's *Milky Way Outline Catalog*, whose own
  license could not be verified; d3-celestial redistributes it under BSD-3-Clause.
- OpenNGC magnitudes are taken as given. Some are implausible (NGC 253 has V 11.1 and B 7.9).
- Sharpless, Barnard and Lynds positions are the centers the catalogues give, to a fraction of the object's
  size: the Spaghetti Nebula (Sh2-240) is 0.4° from the center SIMBAD gives, the Tulip Nebula 0.1°.
  A few Sharpless regions that are parts of one larger object (Sh2-254 to Sh2-258 around IC 2162,
  Sh2-292 and 296 in the Seagull Nebula) are still separate objects.
- Barnard 59, 65, 66 and 67 are the stem of the Pipe Nebula; only Barnard 78, the bowl, carries the name.
- The Lynds opacity is not kept in the data, only its effect on the cut and on `p`.
- The galactic coordinates in VII/7A are wrong for the 21 clouds whose declination lies between -1° and 0°
  (the sign was lost: their latitude grows as the declination falls). Only the equatorial positions are
  used. The Barnard cross-references of the Lynds file are not used either: some pair a cloud with a
  Barnard object 20° away.
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
