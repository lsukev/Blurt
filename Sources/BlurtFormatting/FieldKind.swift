import Foundation

/// What kind of thing the text is being typed into.
///
/// Captured from the accessibility layer when the key goes down, because the shape of the
/// target says something the words don't: nobody puts a sentence in a Name box. A one-line
/// field is a label — a title, a name, a search term — and a label does not end in a full
/// stop, whoever supplied it.
///
/// That last part is why this exists. Cleanup already stopped *appending* a full stop, but
/// Apple's recognizer supplies its own for anything it hears as a complete sentence, and
/// "Disaster recovery test report" is complete enough to qualify. No amount of reasoning
/// about the words fixes that; the target does.
public enum FieldKind: Sendable, Equatable {
    /// `AXTextField` — a name, title, search box, single-line entry.
    case singleLine
    /// `AXTextArea` — prose, a message, a document body.
    case multiLine
    /// Anything else, or nothing focused. Treated exactly as before, so an app with an
    /// unexpected accessibility tree loses nothing rather than getting surprising output.
    case unknown
}

/// Whether a word's trailing period belongs to the word rather than to the sentence.
///
/// Shared deliberately: the stop-stripper needs it so it doesn't amputate "U.S.", and the
/// title-caser needs it so it doesn't then turn "a.m." into "A.m.". Two copies of this rule
/// would drift, and the second failure only shows up in combination with the first.
public enum Abbreviation {

    /// Abbreviations carrying no interior period to give themselves away. "etc." is
    /// structurally identical to "report."; only a list separates them.
    static let known: Set<String> = [
        "etc.", "inc.", "ltd.", "co.", "corp.", "dept.", "est.", "approx.", "vs.",
        "jr.", "sr.", "dr.", "mr.", "mrs.", "ms.", "prof.", "st.", "ave.", "no.",
    ]

    public static func isAbbreviation(_ word: String) -> Bool {
        guard word.hasSuffix(".") else { return false }
        let body = String(word.dropLast())
        if body.contains(".") { return true }                        // U.S., e.g., a.m.
        if body.count == 1, body.first?.isLetter == true { return true }  // Kevin L.
        return known.contains(word.lowercased())
    }
}

public enum TitleCase {

    /// Words that stay lowercase inside a title. First and last word are always capitalized
    /// regardless — "The Report" and "What It Is For", not "the Report".
    static let minorWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "yet", "so",
        "at", "by", "in", "of", "on", "to", "up", "as", "if", "per", "via",
        "from", "into", "onto", "over", "with", "than", "that", "vs",
    ]

    /// True when the text is plainly not prose to be title-cased — an address, a path, a
    /// URL. Cheap insurance against mangling something dictated into a single-line field
    /// that happens not to be a title.
    static func looksLikeIdentifier(_ text: String) -> Bool {
        text.contains("@") || text.contains("://") || text.contains("/") || text.contains("\\")
    }

    public static func apply(to text: String) -> String {
        guard !looksLikeIdentifier(text) else { return text }

        // Split on spaces only, so punctuation and hyphenation ride along with their word.
        let words = text.components(separatedBy: " ")
        let lastIndex = words.count - 1

        let cased = words.enumerated().map { index, word -> String in
            guard !word.isEmpty else { return word }

            // An abbreviation is spelled the way it is spelled. Casing it produces "A.m."
            // and "Etc.", which is worse than leaving it exactly as spoken.
            if Abbreviation.isAbbreviation(word) { return word }

            // Anything already carrying an interior capital is a deliberate spelling —
            // "PDF", "iPhone", "McDonald". Leave it exactly as the speaker had it.
            if word.dropFirst().contains(where: \.isUppercase) { return word }

            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if index != 0, index != lastIndex, minorWords.contains(bare) {
                return word.lowercased()
            }
            return capitalizeFirstLetter(word)
        }
        return cased.joined(separator: " ")
    }

    /// Uppercases the first *letter*, not the first character — so a quoted or parenthesised
    /// word still gets cased on the letter rather than on the bracket.
    private static func capitalizeFirstLetter(_ word: String) -> String {
        guard let index = word.firstIndex(where: \.isLetter) else { return word }
        return word.replacingCharacters(
            in: index...index,
            with: word[index].uppercased()
        )
    }
}
