/// Rules shared by the places that clean up text a person typed or pasted.
enum UserText {
    /// Whether `scalar` is a zero-width non-joiner (U+200C), zero-width joiner (U+200D), left-to-right mark (U+200E) or
    /// right-to-left mark (U+200F).
    ///
    /// Unicode files these under "format", with the invisible characters that can hide text, but they are part of how
    /// people write: Persian and several Indic scripts need the joiners to shape words, emoji sequences such as a family
    /// or a profession are joined by U+200D, and the direction marks keep mixed Arabic and Latin text in order. They stay
    /// in names and notes; the other format characters (zero-width space, bidi embeddings and overrides, isolates, tags)
    /// are still dropped.
    static func isJoinerOrDirectionMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200C, 0x200D, 0x200E, 0x200F: true
        default: false
        }
    }
}
