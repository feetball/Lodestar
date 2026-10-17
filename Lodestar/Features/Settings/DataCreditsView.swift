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
                + "selected the Messier objects, all named objects and the catalog objects brighter than "
                + "magnitude 10; merged duplicates; coordinates in degrees; a few common names added."),
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
    ]
}

/// The credits and licences of the data inside Lodestar, with links to the sources.
struct DataCreditsView: View {
    /// The credit line from ATTRIBUTION.md, shown first.
    private static let creditLine = "Star data: HYG Database v4.1 (astronexus, CC BY-SA 4.0). Deep-sky data: OpenNGC "
        + "by Mattia Verga (CC BY-SA 4.0), compiled from NED, HyperLEDA, SIMBAD, HEASARC and H. Corwin's NGC/IC "
        + "notes. Constellation figures and Milky Way outlines: d3-celestial by Olaf Frohn (BSD-3-Clause), the "
        + "latter after Jose R. Vieira's Milky Way Outline Catalog. Geomagnetic model: WMM2025 by NOAA NCEI and "
        + "the British Geological Survey (public domain). Planetary theory: VSOP87 (Bretagnon & Francou, IMCCE); "
        + "lunar theory after J. Meeus."

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
