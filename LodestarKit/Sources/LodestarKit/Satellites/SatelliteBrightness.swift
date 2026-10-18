import Foundation

/// The apparent brightness of a sunlit satellite.
///
/// **Model.** The standard magnitude convention of satellite observers (McCants/Molczan "intrinsic magnitude",
/// used by Heavens-Above): the *intrinsic magnitude* `m₀` is the magnitude the satellite has at a range of
/// 1000 km when the Sun-satellite-observer angle (the phase angle) is 90°, which Heavens-Above words as "50 %
/// illuminated". At range `ρ` (km) and phase angle `β` the magnitude is
///
///     m = m₀ - 15 + 5·log10(ρ) - 2.5·log10(sin β + (π - β)·cos β)
///
/// The last term is the phase law of a diffuse (Lambertian) sphere, normalized to 1 at β = 90°; a penumbra
/// dims the satellite further by `-2.5·log10(illuminated fraction)`. A real satellite is not a sphere: flat
/// panels and antennas glint, so individual flashes can be several magnitudes brighter and the model is good to
/// about one magnitude for a tumbling body and worse for a stabilized one like the ISS. Atmospheric extinction
/// is not included (add about 0.25 magnitudes per air mass near the horizon).
///
/// **Intrinsic magnitudes.** `intrinsicMagnitude(catalogNumber:)` knows a handful of bright objects; everything
/// else is `nil` (unknown) and then no magnitude is computed. Supply your own value to `Satellite` when you have one.
public enum SatelliteBrightness {
    /// The intrinsic magnitude of the International Space Station: -1.8 at 1000 km and 90° phase (Heavens-Above,
    /// satellite information page of 25544, retrieved 2026-10-18). With the phase law below a pass at 450 km range
    /// and 60° phase comes out at magnitude -4.2, in line with the bright ISS passes seen in practice.
    public static let issIntrinsicMagnitude = -1.8

    /// The intrinsic magnitude of a few well-known bright satellites, or `nil` when unknown. Source for all
    /// entries: Heavens-Above satellite information pages (values "at 1000 km distance, 50 % illuminated"),
    /// retrieved 2026-10-18.
    ///
    /// | NORAD number | Object | Intrinsic magnitude |
    /// |---|---|---|
    /// | 25544 | ISS (ZARYA) | -1.8 |
    /// | 48274 | CSS (TIANHE-1) | 0.0 |
    /// | 20580 | HST | 2.2 |
    public static func intrinsicMagnitude(catalogNumber: Int) -> Double? {
        switch catalogNumber {
        case 25544: issIntrinsicMagnitude
        case 48274: 0.0
        case 20580: 2.2
        default: nil
        }
    }

    /// The apparent magnitude of a satellite (see the model above).
    ///
    /// - Parameters:
    ///   - intrinsicMagnitude: The magnitude at 1000 km and 90° phase.
    ///   - rangeKilometers: Distance from the observer, at least 1 km.
    ///   - phaseAngle: The Sun-satellite-observer angle in degrees, 0 (full) ... 180 (new).
    ///   - illuminatedFraction: The fraction of the Sun's disc that is visible from the satellite
    ///     (`EarthShadow.illuminatedFraction`); 1 outside the shadow.
    /// - Returns: the magnitude, or `nil` when the satellite is not lit (fraction 0), the inputs are not finite or
    ///   out of range, or the phase is so close to 180° that the model's brightness vanishes.
    public static func apparentMagnitude(
        intrinsicMagnitude: Double,
        rangeKilometers: Double,
        phaseAngle: Double,
        illuminatedFraction: Double = 1.0
    ) -> Double? {
        guard intrinsicMagnitude.isFinite, rangeKilometers.isFinite, phaseAngle.isFinite, illuminatedFraction.isFinite else {
            return nil
        }
        if rangeKilometers < 1.0 || phaseAngle < 0.0 || phaseAngle > 180.0 { return nil }
        if !(illuminatedFraction > 0.0) || illuminatedFraction > 1.0 { return nil }
        let beta = phaseAngle * Double.pi / 180.0
        let phaseTerm = sin(beta) + (Double.pi - beta) * cos(beta)
        if !(phaseTerm > 1.0e-6) { return nil }
        return intrinsicMagnitude - 15.0 + 5.0 * log10(rangeKilometers) - 2.5 * log10(phaseTerm) -
            2.5 * log10(illuminatedFraction)
    }
}
