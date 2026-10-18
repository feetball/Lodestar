import SwiftUI

/// A third-party data set or model that ships inside Lodestar.
struct DataCredit: Identifiable, Sendable {
    let id: String
    /// What it is called, e.g. "HYG Database v4.1".
    let name: String
    /// What Lodestar uses it for.
    let usedFor: String
    let author: String
    /// The license's short name, e.g. "CC BY-SA 4.0".
    let license: String
    let licenseURL: URL?
    let sourceURL: URL?
    /// Further acknowledgements and the changes Lodestar made to the data.
    let notice: String
}

extension DataCredit {
    /// CDS's terms for the catalogues it distributes.
    static let cdsTermsURL = URL(string: "https://cds.unistra.fr/vizier-org/licences_vizier.html")

    static let all: [DataCredit] = [
        DataCredit(
            id: "hyg", name: "HYG Database v4.1", usedFor: "Stars",
            author: "astronexus, maintainer of the HYG Database",
            license: "CC BY-SA 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/"),
            sourceURL: URL(string: "https://www.astronexus.com/hyg"),
            notice: "Compiled by its maintainer from the Hipparcos catalogue (ESA), the Yale Bright Star Catalog and "
                + "the Gliese\u{2013}Jahreiss Catalogue of Nearby Stars. Changes for Lodestar: converted to compact "
                + "JSON; kept every star brighter than magnitude 6.5 and every named star; right ascension in "
                + "degrees; Bayer designations in Greek letters; Hipparcos right ascensions corrected for proper "
                + "motion; sorted by magnitude."),
        DataCredit(
            id: "openngc", name: "OpenNGC", usedFor: "Deep-sky objects",
            author: "Mattia Verga and contributors",
            license: "CC BY-SA 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/"),
            sourceURL: URL(string: "https://github.com/mattiaverga/OpenNGC"),
            notice: "Compiled from the NASA/IPAC Extragalactic Database (NED), HyperLEDA, SIMBAD (CDS, Strasbourg), "
                + "HEASARC and Harold Corwin's NGC/IC notes. Changes for Lodestar: converted to compact JSON; "
                + "selected the Messier objects, all named objects, the catalog objects brighter than magnitude 11.5 "
                + "and the larger nebulae and clusters; merged duplicates; coordinates in degrees; a few common "
                + "names added. The Caldwell numbers come from OpenNGC\u{2019}s identifiers."),
        DataCredit(
            id: "sharpless", name: "Sharpless 2 catalogue", usedFor: "Emission nebulae (H II regions)",
            author: "S. Sharpless, via CDS (VII/20)",
            license: "CDS terms of use", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://cdsarc.cds.unistra.fr/viz-bin/cat/VII/20"),
            notice: "S. Sharpless, A Catalogue of H II Regions, Astrophysical Journal Supplement 4, 257 (1959). A "
                + "factual compilation (positions, sizes, classes) distributed by CDS, Strasbourg, through VizieR."),
        DataCredit(
            id: "barnard", name: "Barnard dark nebulae", usedFor: "Dark nebulae",
            author: "E. E. Barnard, via CDS (VII/220A)",
            license: "CDS terms of use", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://cdsarc.cds.unistra.fr/viz-bin/cat/VII/220A"),
            notice: "E. E. Barnard, A Photographic Atlas of Selected Regions of the Milky Way (1927). The "
                + "machine-readable version is by J. Takahashi and M. Ohishi (NAOJ), with diameters and notes by "
                + "Bill Gray and corrections by Mati Morel, distributed by CDS, Strasbourg, through VizieR."),
        DataCredit(
            id: "lynds", name: "Lynds dark nebulae", usedFor: "Dark nebulae and dark clouds",
            author: "B. T. Lynds, via CDS (VII/7A)",
            license: "CDS terms of use", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://cdsarc.cds.unistra.fr/viz-bin/cat/VII/7A"),
            notice: "B. T. Lynds, Catalogue of Dark Nebulae, Astrophysical Journal Supplement 7, 1 (1962), prepared "
                + "by J. Marcout and F. Ochsenbein from T. Nagy\u{2019}s version at the Astronomical Data Center. "
                + "Lodestar uses the clouds of opacity 6 or larger than one square degree, and the named ones. "
                + "Distributed by CDS, Strasbourg, through VizieR."),
        DataCredit(
            id: "dias", name: "Optically visible open clusters and candidates", usedFor: "Open clusters",
            author: "W. S. Dias and co-authors, via CDS (B/ocl)",
            license: "CDS terms of use", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://cdsarc.cds.unistra.fr/viz-bin/cat/B/ocl"),
            notice: "W. S. Dias, B. S. Alessi, A. Moitinho and J. R. D. L\u{00E9}pine, Astronomy & Astrophysics 389, "
                + "871 (2002), version 3.5. Lodestar uses a selection of Collinder, Melotte, Trumpler and Stock "
                + "clusters. Distributed by CDS, Strasbourg, through VizieR."),
        DataCredit(
            id: "iau-boundaries", name: "Constellation boundaries", usedFor: "The constellation of a deep-sky object",
            author: "N. G. Roman, after E. Delporte, via CDS (VI/42)",
            license: "CDS terms of use", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://cdsarc.cds.unistra.fr/viz-bin/cat/VI/42"),
            notice: "N. G. Roman, Identification of a constellation from a position, Publications of the "
                + "Astronomical Society of the Pacific 99, 695 (1987), after the boundaries of the IAU adopted from "
                + "E. Delporte (1930). Used for the objects that OpenNGC does not place in a constellation. "
                + "Distributed by CDS, Strasbourg, through VizieR."),
        DataCredit(
            id: "vizier", name: "VizieR catalogue access tool", usedFor: "Distribution of the five catalogues above",
            author: "CDS, Strasbourg, France",
            license: "Acknowledgement requested", licenseURL: DataCredit.cdsTermsURL,
            sourceURL: URL(string: "https://vizier.cds.unistra.fr/"),
            notice: "This research has made use of the VizieR catalogue access tool, CDS, Strasbourg, France "
                + "(DOI: 10.26093/cds/vizier). The original description of the VizieR service was published in 2000, "
                + "A&AS 143, 23."),
        DataCredit(
            id: "d3-celestial", name: "d3-celestial", usedFor: "Constellation figures and Milky Way outlines",
            author: "Olaf Frohn",
            license: "BSD 3-Clause", licenseURL: URL(string: "https://opensource.org/license/bsd-3-clause"),
            sourceURL: URL(string: "https://github.com/ofrohn/d3-celestial"),
            notice: "Constellation names and figures follow the IAU constellation page. The Milky Way outlines are "
                + "after Jose R. Vieira's Milky Way Outline Catalog. Lodestar simplified the outlines and corrected a "
                + "few names; the license text is below."),
        DataCredit(
            id: "wmm", name: "World Magnetic Model 2025", usedFor: "True north and magnetic interference",
            author: "NOAA NCEI and the British Geological Survey",
            license: "Public domain", licenseURL: nil,
            sourceURL: URL(string: "https://www.ncei.noaa.gov/products/world-magnetic-model"),
            notice: "A work of the US Government. Valid from 2025 to 2030."),
        DataCredit(
            id: "ephemeris", name: "VSOP87 and lunar theory", usedFor: "Planets and Moon",
            author: "Bretagnon & Francou (IMCCE); Jean Meeus",
            license: "Published scientific theories", licenseURL: nil, sourceURL: nil,
            notice: "VSOP87 planetary theory (Astronomy & Astrophysics 202, 309, 1988) and the lunar theory of "
                + "Meeus, Astronomical Algorithms, 2nd ed. Planetary magnitudes follow Mallama & Hilton (2018)."),
        DataCredit(
            id: "imo", name: "IMO Meteor Shower Calendar 2026", usedFor: "Meteor showers",
            author: "International Meteor Organization, edited by J\u{00FC}rgen Rendtel",
            license: "Published data, cited with credit", licenseURL: nil,
            sourceURL: URL(string: "https://www.imo.net"),
            notice: "The activity periods, peak times, rates, radiant positions and drift, and entry speeds of the "
                + "meteor showers are entered by hand from the 2026 Meteor Shower Calendar (IMO INFO 3-25, "
                + "\u{00A9} International Meteor Organization). The radiant drift rates are least-squares fits to the "
                + "calendar's radiant tables."),
    ]
}

/// The credits and licences of the data inside Lodestar, with links to the sources.
struct DataCreditsView: View {
    /// The credit line from ATTRIBUTION.md, shown first.
    private static let creditLine = "Star data: HYG Database v4.1 (astronexus, CC BY-SA 4.0). Deep-sky data: OpenNGC "
        + "by Mattia Verga (CC BY-SA 4.0), compiled from NED, HyperLEDA, SIMBAD, HEASARC and H. Corwin's NGC/IC "
        + "notes, with the Sharpless 2, Barnard and Lynds nebula catalogues, the open clusters of Dias et al. and "
        + "the constellation boundaries of Roman and Delporte, distributed by CDS through VizieR. This research has "
        + "made use of the VizieR catalogue access tool, CDS, Strasbourg, France (DOI: 10.26093/cds/vizier; "
        + "original description: A&AS 143, 23, 2000). Constellation figures and Milky Way outlines: d3-celestial "
        + "by Olaf Frohn (BSD-3-Clause), the latter after Jose R. Vieira's Milky Way Outline Catalog. Meteor "
        + "showers: IMO Meteor Shower Calendar 2026 (\u{00A9} International Meteor Organization). Geomagnetic "
        + "model: WMM2025 by NOAA NCEI and the British Geological Survey (public domain). Planetary theory: "
        + "VSOP87 (Bretagnon & Francou, IMCCE); lunar theory after J. Meeus."

    private static let bsdLicense = """
        Copyright (c) 2015, Olaf Frohn
        All rights reserved.

        Redistribution and use in source and binary forms, with or without modification, are permitted provided \
        that the following conditions are met:

        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the \
        following disclaimer.

        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and \
        the following disclaimer in the documentation and/or other materials provided with the distribution.

        3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or \
        promote products derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED \
        WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A \
        PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR \
        ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT \
        LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS \
        INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR \
        TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF \
        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """

    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            SettingsSection(title: "Credits", footer: "Links open in Safari.") {
                Text(Self.creditLine)
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(DataCredit.all) { credit in
                SettingsSection(title: credit.name) {
                    InfoRow(label: "Used for", value: credit.usedFor)
                    InfoRow(label: "By", value: credit.author)
                    InfoRow(label: "License", value: credit.license)
                    SettingsCaption(credit.notice)
                    if let licenseURL = credit.licenseURL {
                        Link(destination: licenseURL) {
                            Label("Read the license", systemImage: "doc.text")
                        }
                    }
                    if let sourceURL = credit.sourceURL {
                        Link(destination: sourceURL) {
                            Label("Open the source", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            SettingsSection(
                title: "BSD 3-Clause License (d3-celestial)",
                footer: "The CC BY-SA 4.0 data files stay under that license: anyone who passes them on must keep "
                    + "these credits, say what they changed, and license them the same way.") {
                Text(Self.bsdLicense)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .themedList(palette)
        .navigationTitle("Data Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
