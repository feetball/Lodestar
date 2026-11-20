import Foundation

/// What Siri and Shortcuts say for "When is it dark": tonight's darkness, the Moon and the Milky Way core, in the words
/// of the widgets (`TonightLines`), for a place.
enum DarkTonightWords {
    /// Said when the app does not know where the observer is.
    static let noPlace = "Lodestar does not know where you are yet. Open Lodestar once to allow location, "
        + "then ask again."

    /// The night under way, or the coming one once the Sun has risen on the night before, at `date`. Costs about as
    /// much as one widget entry: a night summary and a search for events.
    static func sentence(for place: TonightPlace, at date: Date) -> String {
        guard case .night(let night) = TonightBuilder.entry(for: place, at: date).content else { return noPlace }
        let lines = TonightLines(night: night, now: date)
        return [lines.dark.spoken, lines.moon.spoken, lines.core.spoken].joined(separator: " ")
    }
}
