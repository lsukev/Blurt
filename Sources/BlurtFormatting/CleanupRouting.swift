import Foundation

/// Decides whether an utterance is worth sending to the on-device model.
///
/// Measured: the model costs 420–1435 ms depending on how much there is to regenerate,
/// against microseconds for the rule pass. That is worth paying when the model can do
/// something the rules cannot, and pure waiting when it cannot.
///
/// The tempting rule is "skip the model for short text", and it is wrong. "Send it Tuesday,
/// actually Wednesday" is five words and needs the model — no regex can apply a spoken
/// self-correction. Length is a poor proxy for difficulty, so the question asked here is
/// narrower: *is there anything in this utterance the rules would visibly fail at?*
public enum CleanupRouting {

    /// Above this, prose is likely enough to have structure — lists, clauses, paragraphs —
    /// that the model handles better than the rules do.
    static let shortUtteranceWords = 12

    /// Phrases that signal a spoken correction. Applying one means understanding which part
    /// of the sentence is being replaced, which is squarely a model job.
    static let correctionMarkers = [
        "actually", "i mean", "no wait", "scratch that", "rather", "correction",
        "make that", "sorry",
    ]

    /// Fillers the rule pass deliberately refuses to strip, because they are also ordinary
    /// words. "I like this" and "it was, like, fine" are the same token to a regex and
    /// different to the model.
    static let ambiguousFillers = ["like", "you know", "kind of", "sort of", "basically", "literally"]

    /// - Returns: true when the model should run.
    public static func needsModel(_ text: String, tone: ToneMode, field: FieldKind) -> Bool {
        // Casual and Formal exist to rewrite. The rules cannot rewrite anything, so
        // skipping the model would silently ignore the setting.
        guard tone == .asSpoken else { return true }

        let lowered = text.lowercased()
        if correctionMarkers.contains(where: { lowered.contains($0) }) { return true }
        if ambiguousFillers.contains(where: { containsWord($0, in: lowered) }) { return true }

        let words = text.split(whereSeparator: \.isWhitespace).count
        if words > shortUtteranceWords { return true }

        // Short, no corrections, no ambiguous fillers, no rewriting asked for. The rule
        // pass already handles the rest — title case, digits, punctuation, spacing — and it
        // does so in microseconds.
        return false
    }

    /// Matches on word boundaries so "like" does not fire inside "likely" and "unlike".
    static func containsWord(_ phrase: String, in text: String) -> Bool {
        let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init)
        let parts = phrase.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return words.contains(phrase) }
        // Multi-word phrases: look for the sequence.
        guard words.count >= parts.count else { return false }
        for start in 0...(words.count - parts.count) {
            if Array(words[start..<(start + parts.count)]) == parts { return true }
        }
        return false
    }
}
