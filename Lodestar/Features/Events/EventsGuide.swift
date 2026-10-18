import Foundation
import LodestarKit

/// The words of an event's detail screen: what the event is, why it is worth a photograph and how to take it.
struct EventsGuide: Sendable, Equatable {
    /// What the event is.
    let about: String
    /// Why it is worth photographing.
    let why: String
    /// Practical advice, one sentence each.
    let tips: [String]
}

extension EventsGuide {
    /// The text for `entry`. `isSouthernHemisphere` words the seasons.
    static func make(for entry: EventsEntry, isSouthernHemisphere: Bool) -> EventsGuide {
        switch entry.event.details {
        case .meteorShower(let peak):
            return meteorShower(peak, interference: entry.moonInterference)
        case .conjunction(let conjunction):
            return self.conjunction(conjunction)
        case .opposition(let opposition):
            return self.opposition(opposition)
        case .greatestElongation(let elongation):
            return self.elongation(elongation)
        case .earthApsis(let apsis):
            return self.apsis(apsis)
        case .season(let season):
            return self.season(season.kind, isSouthernHemisphere: isSouthernHemisphere)
        case .fullMoonSpecial(let special):
            return fullMoon(special)
        case .lunarEclipse(let eclipse):
            return lunarEclipse(eclipse)
        case .solarEclipse(let eclipse):
            return solarEclipse(eclipse, local: eclipse.local)
        }
    }

    // MARK: Meteor showers

    private static func meteorShower(_ peak: MeteorShowerPeak, interference: EventsMoonInterference?) -> EventsGuide {
        let shower = peak.shower
        var tips = [
            "Use a wide lens (14 to 24 mm) at its widest aperture, ISO 1600 to 6400 and 10 to 20 seconds per frame, "
                + "on a tripod.",
            "Aim about 40\u{00B0} away from the radiant, not at it: meteors then draw long trails across the frame.",
            "Shoot after midnight, when your side of the Earth turns into the stream and the radiant climbs high.",
            "Let the camera run for hours and keep the frames that caught a meteor. A time-lapse of the whole night "
                + "works too.",
        ]
        if let interference, interference.level != .moonDown, interference.level != .little {
            tips.append("Moonlight hides faint meteors. Frame away from the Moon, or shoot after it sets.")
        }
        return EventsGuide(
            about: "\(shower.name) is a meteor shower. The Earth crosses a trail of dust left by a comet or an asteroid, "
                + "and the grains burn up as meteors that seem to fly out of one point in the sky, the radiant. "
                + "Under a perfectly dark sky it can show up to about \(shower.zhr) meteors an hour at its peak.",
            why: "Meteors come at random and last a fraction of a second, so the way to catch them is to let a camera "
                + "run: a fixed wide-angle frame every few seconds for hours.",
            tips: tips)
    }

    // MARK: Conjunctions

    private static func conjunction(_ conjunction: Conjunction) -> EventsGuide {
        let first = conjunction.first.displayName
        let second = conjunction.second.displayName
        let separation = AppFormat.separation(conjunction.separation)
        let focalLength = Int(EventsCalculator.suggestedFocalLength(separation: conjunction.separation))
        let about: String
        if conjunction.involvesMoon {
            about = "The Moon passes \(separation) from \(second), as seen from the centre of the Earth. "
                + "It moves its own width in about an hour, so the pair changes while you watch."
        } else {
            about = "\(first) and \(second) come within \(separation) of each other in the sky. They are still "
                + "hundreds of millions of kilometres apart: it is only a matter of the line of sight."
        }
        var tips = [
            "Frame both. They are \(separation) apart, so about \(focalLength) mm (35 mm equivalent) holds the pair "
                + "with room around it.",
        ]
        if conjunction.solarElongation < 45 {
            tips.append("The pair stands only \(AngleFormatter.formatDegrees(conjunction.solarElongation, decimals: 0)) "
                        + "from the Sun, so it is low in twilight. Scout a clear horizon first.")
        }
        if conjunction.involvesMoon {
            tips.append("The Moon is far brighter than a planet or a star. Bracket your exposures, or blend a short "
                        + "and a long frame.")
        }
        if let topocentric = conjunction.topocentric, topocentric.isOccultation {
            tips.append("From here the Moon passes in front of \(second): an occultation. Start recording several "
                        + "minutes before.")
        } else if conjunction.occultationPossible {
            tips.append("The Moon covers \(second) from parts of the Earth, but not as seen from here.")
        }
        return EventsGuide(
            about: about,
            why: "A close pair makes a strong picture: both over a landscape with a wide lens, or tight together "
                + "with a telephoto.",
            tips: tips)
    }

    // MARK: Planets

    private static func opposition(_ opposition: Opposition) -> EventsGuide {
        let planet = opposition.planet.displayName
        let size = opposition.angularDiameterArcseconds.formatted(.number.precision(.fractionLength(1)))
        let about = "\(planet) is opposite the Sun in the sky. It rises at sunset, is highest at midnight and is at its "
            + "closest to the Earth for this year, so it is as bright and as large as it gets (\(size)\u{2033} across)."
        if opposition.planet == .uranus || opposition.planet == .neptune {
            return EventsGuide(
                about: about,
                why: "The best time of the year to catch a distant planet: it is at its brightest, and in the sky all night.",
                tips: [
                    "\(planet) looks like a faint star. Find it with a star chart, then confirm it by its slow movement "
                        + "from night to night.",
                    "Use a tripod, a 135 to 300 mm lens and exposures of 5 to 10 seconds, or stack several frames.",
                    "Wait until \(planet) is high, around midnight, and the Moon is away.",
                ])
        }
        return EventsGuide(
            about: about,
            why: "The best weeks of the year to photograph \(planet), with the most detail and the longest nights to "
                + "work in.",
            tips: [
                "Use the longest focal length you have, 400 mm or more, or a telescope.",
                "Shoot video or bursts and stack the sharpest frames: the air blurs single shots.",
                "Wait until \(planet) is high, around midnight, when the air is steadiest.",
            ])
    }

    private static func elongation(_ elongation: GreatestElongation) -> EventsGuide {
        let planet = elongation.planet.displayName
        let angle = AngleFormatter.formatDegrees(elongation.angle, decimals: 0)
        let evening = elongation.direction == .east
        return EventsGuide(
            about: "\(planet) is as far from the Sun as it gets in this apparition: \(angle) "
                + "\(evening ? "east" : "west") of it, in the \(evening ? "evening" : "morning") sky.",
            why: "The easiest time to see and photograph \(planet): it is as far out of the Sun's glare as it ever "
                + "gets, and it hangs in the twilight.",
            tips: [
                evening ? "Look low in the west after sunset." : "Look low in the east before sunrise.",
                "A clear horizon matters more than the lens. Try 100 to 300 mm, or a wide lens with a landscape.",
                "Start shooting in the twilight: the planet is easy to find then, and fades into the glow later.",
            ])
    }

    private static func apsis(_ apsis: EarthApsis) -> EventsGuide {
        let nearest = apsis.kind == .perihelion
        return EventsGuide(
            about: "The Earth is \(nearest ? "closest to" : "farthest from") the Sun, "
                + "\(apsis.distanceAU.formatted(.number.precision(.fractionLength(3)))) AU away. The distance changes "
                + "the Sun's size in the sky by only about 3 percent.",
            why: "Nothing to see in the sky, but a date to know if you compare the Sun's size through the year.",
            tips: [])
    }

    // MARK: Seasons

    private static func season(_ kind: SeasonKind, isSouthernHemisphere: Bool) -> EventsGuide {
        switch kind {
        case .marchEquinox, .septemberEquinox:
            let spring = (kind == .marchEquinox) != isSouthernHemisphere
            return EventsGuide(
                about: "The Sun crosses the celestial equator: the \(spring ? "vernal" : "autumnal") equinox for your "
                    + "hemisphere. Day and night are nearly equal everywhere, and the Sun rises due east and sets "
                    + "due west.",
                why: "Plan a sunrise or sunset over a landmark that lines up with due east or west, and compare the "
                    + "Sun's path with the solstices.",
                tips: [
                    "Scout the spot a day or two before. The Sun moves along the horizon by about its own width a day.",
                    "Use a long lens from far away for a large Sun next to the landmark.",
                    "Shoot the Sun only when it is low and dim, and use a solar filter for anything higher.",
                ])
        case .juneSolstice, .decemberSolstice:
            let summer = (kind == .juneSolstice) != isSouthernHemisphere
            let nightTip = summer ? "The night is short, so plan star photography early or late."
                                  : "The long night leaves plenty of dark time for star photography."
            return EventsGuide(
                about: "The Sun reaches its \(kind == .juneSolstice ? "northernmost" : "southernmost") point. For your "
                    + "hemisphere this is the \(summer ? "summer" : "winter") solstice: the "
                    + "\(summer ? "longest" : "shortest") day and the \(summer ? "shortest" : "longest") night.",
                why: "The Sun rises and sets at the far end of its swing along the horizon, which lines it up with "
                    + "landmarks it meets only on this day.",
                tips: [
                    "Check where the Sun rises and sets on this date, and scout the spot beforehand.",
                    nightTip,
                    "Shoot the Sun only when it is low and dim, and use a solar filter for anything higher.",
                ])
        }
    }

    // MARK: The Moon

    private static func fullMoon(_ special: FullMoonSpecial) -> EventsGuide {
        let distance = special.distanceKilometers.formatted(.number.precision(.fractionLength(0)))
        var parts: [String] = []
        for category in special.categories {
            switch category {
            case .supermoon:
                parts.append("a supermoon: full while close to the Earth (\(distance) km), so a little larger and "
                             + "brighter than an average full Moon")
            case .micromoon:
                parts.append("a micromoon: full while far from the Earth (\(distance) km), so a little smaller than "
                             + "an average full Moon")
            case .blueMoon:
                parts.append("a blue moon: the second full Moon of its calendar month. It is not actually blue")
            }
        }
        let about = parts.isEmpty ? "A special full Moon."
            : "A full Moon that is " + parts.joined(separator: ", and ") + "."
        return EventsGuide(
            about: about,
            why: "A big Moon rising behind a landmark is a classic picture, and the full Moon is up all night.",
            tips: [
                "Shoot it as it rises, from far away with a long lens (200 to 600 mm), so it looks large next to "
                    + "the foreground.",
                "A full Moon is bright: start at ISO 100, f/8 and 1/125 s, then adjust.",
                "To keep the landscape too, blend a short and a long frame, or shoot just after sunset.",
                special.categories.contains(.supermoon)
                    ? "The size difference is small. Put a landmark of known size in the frame to show it." : nil,
            ].compactMap { $0 })
    }

    private static func lunarEclipse(_ eclipse: LunarEclipse) -> EventsGuide {
        let about: String
        switch eclipse.kind {
        case .total:
            about = "The whole Moon enters the dark core of the Earth's shadow and glows a dim copper red for "
                + "\(AngleFormatter.formatDuration(seconds: eclipse.totalDuration))."
        case .partial:
            about = "Part of the Moon enters the dark core of the Earth's shadow and looks bitten away "
                + "(umbral magnitude \(EventsFormat.magnitude(eclipse.umbralMagnitude)))."
        case .penumbral:
            about = "The Moon passes through the faint outer shadow of the Earth and dims only slightly. "
                + "The change is hard to see."
        }
        var tips = [
            "Use a long lens (200 to 600 mm) on a sturdy tripod for the Moon alone, or a wide lens to put the "
                + "Moon over a landscape.",
            "Shoot a frame every minute or two and combine them into a sequence.",
            "No filter is needed: a lunar eclipse is safe to watch and to photograph.",
        ]
        if eclipse.kind != .penumbral {
            tips.insert("The exposure changes a lot: about 1/500 s at ISO 200 before the shadow, seconds at "
                        + "ISO 1600 or more in the shadow. Check the histogram.", at: 1)
        }
        return EventsGuide(
            about: about,
            why: "The Moon changes shape and colour over a few hours, which makes a good sequence. A total eclipse "
                + "puts a red Moon among the stars.",
            tips: tips)
    }

    // MARK: Solar eclipses

    private static func solarEclipse(_ eclipse: SolarEclipse, local: LocalSolarCircumstances?) -> EventsGuide {
        var about: String
        switch eclipse.kind {
        case .total:
            about = "The Moon covers the Sun completely along a narrow path across the Earth."
        case .annular:
            about = "The Moon crosses in front of the Sun but is too far away to cover it, leaving a ring of sunlight."
        case .hybrid:
            about = "The eclipse is annular in some places and total in others along its path."
        case .partial:
            about = "The Moon covers only part of the Sun, as seen from anywhere on the Earth."
        }
        if let local {
            switch local.kind {
            case .none:
                about += " It cannot be seen from here."
            case .partial:
                about += " From here it is partial: \(AppFormat.percent(local.obscuration)) of the Sun is covered at "
                    + "most."
            case .annular:
                about += " From here it is annular, for \(AngleFormatter.formatDuration(seconds: local.centralDuration))."
            case .total:
                about += " From here it is total, for \(AngleFormatter.formatDuration(seconds: local.centralDuration))."
            }
        }
        let why: String
        switch eclipse.kind {
        case .total, .hybrid:
            why = "One of the most dramatic sights in the sky. In totality the Sun's corona shows around the black Moon."
        case .annular:
            why = "The Moon sits inside the Sun's disc and leaves a bright ring, the \u{201C}ring of fire\u{201D}."
        case .partial:
            why = "The Sun turns into a crescent. Light through leaves and gaps also throws small crescents on the ground."
        }
        return EventsGuide(
            about: about,
            why: why,
            tips: [
                "Fit a certified solar filter over the front of the lens before the partial phase begins, and keep it "
                    + "on. Only the brief totality of a total eclipse can be shot without it.",
                "The Sun is half a degree wide: a 300 to 600 mm lens fills a good part of the frame.",
                "Never look at the Sun through the viewfinder, binoculars or a telescope without a certified filter. "
                    + "Use the screen on the back instead.",
                "Rehearse your settings and the order of the shots in daylight beforehand.",
            ])
    }
}
