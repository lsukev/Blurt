import Foundation

/// Turns spoken numbers into digits: "twenty twenty six" becomes 2026.
///
/// Apple's recognizer writes numbers as words, which is wrong for most of what people
/// dictate into a name field — "2026 Data Center and Report" came back as "Twenty twenty
/// six Data Center and Report". There is no option to change that; `SpeechTranscriber`
/// exposes only `etiquetteReplacements`. So it is done here.
public enum SpokenNumbers {

    /// Below this, words read better than digits — "three people", not "3 people". Years
    /// and quantities worth writing numerically are all above it.
    static let digitThreshold = 10

    static let units: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    static func isNumberWord(_ word: String) -> Bool {
        let w = word.lowercased()
        return units[w] != nil || tens[w] != nil || scales[w] != nil
    }

    // MARK: - Entry point

    public static func digitize(_ text: String) -> String {
        // Split on spaces only. Punctuation stays attached to its word and is peeled off
        // per token, so "in 2026," keeps its comma.
        let tokens = text.components(separatedBy: " ")
        var output: [String] = []
        var index = 0

        while index < tokens.count {
            guard let run = numberRun(in: tokens, from: index) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            let words = tokens[run].map { stripped($0) }
            guard let value = parse(words), value >= digitThreshold else {
                output.append(contentsOf: tokens[run])
                index = run.upperBound
                continue
            }
            // Whatever punctuation trailed the last spoken word belongs to the sentence,
            // not the number, so it rides along.
            let trailing = trailingPunctuation(of: tokens[run.upperBound - 1])
            output.append("\(value)\(trailing)")
            index = run.upperBound
        }
        return output.joined(separator: " ")
    }

    // MARK: - Run detection

    /// The maximal span of number words starting at `start`, or nil if there isn't one.
    ///
    /// "and" is admitted only when number words sit on *both* sides of it. That is the
    /// difference between "two hundred and five" — one number — and "Data Center and
    /// Report", where swallowing the conjunction would destroy the title.
    static func numberRun(in tokens: [String], from start: Int) -> Range<Int>? {
        guard isNumberWord(stripped(tokens[start])) else { return nil }

        var end = start + 1
        while end < tokens.count {
            let word = stripped(tokens[end]).lowercased()
            if isNumberWord(word) {
                end += 1
            } else if word == "and",
                      end + 1 < tokens.count,
                      isNumberWord(stripped(tokens[end + 1])) {
                end += 2
            } else {
                break
            }
        }

        // A number that ended mid-sentence — "in 2026, we shipped" — must not run on into
        // the next clause, so a token carrying sentence punctuation closes the span.
        for i in start..<end where endsClause(tokens[i]) {
            return start..<(i + 1)
        }
        return start..<end
    }

    // MARK: - Parsing

    static func parse(_ words: [String]) -> Int? {
        let parts = words.map { $0.lowercased() }.filter { $0 != "and" }
        guard !parts.isEmpty else { return nil }
        if let year = parseYear(parts) { return year }
        return parseCardinal(parts)
    }

    /// Years are spoken as two halves — "nineteen ninety nine", "twenty twenty six" — which
    /// cardinal parsing cannot represent: it would read the second half as a continuation
    /// and produce nonsense. Recognized only when both halves are two-digit and no scale
    /// word appears, so "forty two" stays 42 rather than becoming 4002.
    static func parseYear(_ parts: [String]) -> Int? {
        guard parts.count >= 2, !parts.contains(where: { scales[$0] != nil }) else { return nil }

        guard let lead = tens[parts[0]] ?? units[parts[0]], (10...99).contains(lead) else {
            return nil
        }
        guard let tail = parseCardinal(Array(parts.dropFirst())), (0...99).contains(tail) else {
            return nil
        }
        // "twenty oh five" is 2005; "twenty five" is 25, not 2005 — a bare unit after a
        // tens word is a continuation of it, which cardinal parsing already handles.
        let secondIsTensOrOh = tens[parts[1]] != nil || parts[1] == "oh" || (units[parts[1]] ?? 0) >= 10
        guard secondIsTensOrOh else { return nil }

        return lead * 100 + tail
    }

    static func parseCardinal(_ parts: [String]) -> Int? {
        var total = 0
        var current = 0
        var sawAnything = false

        for word in parts {
            if let unit = units[word] {
                current += unit
                sawAnything = true
            } else if let ten = tens[word] {
                current += ten
                sawAnything = true
            } else if let scale = scales[word] {
                guard sawAnything else { return nil }
                if scale == 100 {
                    current *= 100
                } else {
                    total += max(current, 1) * scale
                    current = 0
                }
            } else {
                return nil
            }
        }
        guard sawAnything else { return nil }
        return total + current
    }

    // MARK: - Tokens

    static func stripped(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters)
    }

    static func trailingPunctuation(of token: String) -> String {
        String(token.reversed().prefix { $0.isPunctuation }.reversed())
    }

    static func endsClause(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".,;:!?".contains(last)
    }
}
