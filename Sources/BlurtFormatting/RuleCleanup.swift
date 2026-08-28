import Foundation

/// Deterministic, zero-latency cleanup of a raw transcript.
///
/// This is the fallback when the on-device model is unavailable — which, on any Mac without
/// Apple Intelligence enabled, means it is the *only* cleanup that ever runs. It had no
/// tests while living in the app target, which is how it shipped appending a full stop to
/// every one-word answer.
public enum RuleCleanup {

    /// Standalone filler words, stripped only when surrounded by word boundaries.
    ///
    /// Deliberately short and unambiguous. "like" and "you know" belong here in spirit and
    /// cannot be added in practice: a word-boundary regex cannot tell "I like this" from
    /// "it was, like, fine". That distinction needs the sentence, which is the model's job.
    static let fillers = ["um", "uh", "erm", "uhm", "hmm", "mhm"]

    static let spokenPunctuation: [(String, String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("open paren", " ("),
        ("close paren", ") "),
    ]

    public static func apply(_ raw: String, field: FieldKind = .unknown) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = stripFillers(from: text)
        text = applySpokenPunctuation(to: text)
        text = collapseWhitespace(in: text)

        // A one-line field holds a label, not a sentence. Title-case it and strip the
        // terminal stop — including one the engine supplied, which is the case no amount of
        // reasoning about the words can catch.
        if field == .singleLine {
            text = TitleCase.apply(to: stripTerminalStop(text))
            return text
        }

        text = capitalizeSentences(in: text)
        text = addQuestionMarkIfNeeded(text)

        return text
    }

    /// Removes a trailing full stop, unless it belongs to the final word.
    ///
    /// Question and exclamation marks stay — someone dictating "Is this right?" into a
    /// search box meant the mark, whereas nobody means the stop.
    static func stripTerminalStop(_ text: String) -> String {
        guard text.hasSuffix(".") else { return text }
        let finalWord = text.components(separatedBy: " ").last ?? text
        guard !Abbreviation.isAbbreviation(finalWord) else { return text }
        return String(text.dropLast())
    }

    // MARK: - Terminal punctuation

    /// Question words that are almost never anything else at the start of a sentence.
    static let interrogatives: Set<String> = [
        "what", "who", "whom", "whose", "where", "when", "why", "how", "which",
    ]

    /// Auxiliaries that begin a question only when a subject follows.
    static let auxiliaries: Set<String> = [
        "is", "are", "was", "were", "do", "does", "did", "can", "could",
        "should", "would", "will", "have", "has", "had", "am", "may", "might",
    ]

    static let subjects: Set<String> = [
        "you", "we", "they", "he", "she", "it", "i", "there", "that", "this", "these", "those",
    ]

    /// Adds `?` to something that is plainly a question, and adds nothing otherwise.
    ///
    /// It deliberately never appends a full stop. This runs *after* the speech engine, and
    /// Apple's recognizer already punctuates what it hears as a sentence — so reaching this
    /// point unpunctuated means the engine judged the utterance a fragment. Appending a stop
    /// there overrides that judgement in exactly the cases it was most likely right about:
    /// one-word answers, names, search terms, chat messages.
    ///
    /// A question mark is different. The engine genuinely does miss those, and getting one
    /// wrong costs a character rather than changing what the sentence claims.
    static func addQuestionMarkIfNeeded(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return isQuestion(text) ? text + "?" : text
    }

    static func isQuestion(_ text: String) -> Bool {
        // Only the final clause matters: "I'm done. What time is it" is a question.
        let clause = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .last?
            .trimmingCharacters(in: .whitespaces) ?? text

        let words = clause
            .lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard let first = words.first else { return false }
        if interrogatives.contains(first) {
            // "How to fix this" and "what a mess" are not questions.
            if words.count > 1, ["to", "a", "an"].contains(words[1]) { return false }
            return words.count > 1
        }
        // An auxiliary alone is usually an imperative — "have a good day", "do your best".
        // It only reads as a question when a subject follows it.
        if auxiliaries.contains(first), words.count > 1, subjects.contains(words[1]) {
            return true
        }
        return false
    }

    // MARK: - Passes

    static func stripFillers(from text: String) -> String {
        var result = text
        for filler in fillers {
            let pattern = "(?i)(?<![\\w'])\(filler)\\b,?"
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    static func applySpokenPunctuation(to text: String) -> String {
        var result = text
        for (phrase, replacement) in spokenPunctuation {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(phrase)\\b", with: replacement, options: .regularExpression
            )
        }
        return result
    }

    static func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) { capitalizeNext = true }
            }
        }
        return result
    }
}
