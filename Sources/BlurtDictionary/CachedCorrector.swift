import Foundation

/// A `DictionaryCorrector` that is rebuilt only when the entries actually change.
///
/// Building one compiles a regex per rule, and that is not the cheap operation the previous
/// comment claimed. Measured on this machine:
///
/// | entries | build   | apply  |
/// |---------|---------|--------|
/// | 10      | 5.7 ms  |  11 µs |
/// | 40      | 21.5 ms |  46 µs |
/// | 100     | 54.0 ms | 119 µs |
///
/// Rebuilding per dictation put all of that between releasing the key and seeing text —
/// 99.8% of the dictionary's cost, spent recompiling patterns that had not changed.
///
/// The objection to caching was staleness, and it was a fair one: a corrector that outlives
/// an edit silently produces text the user's own dictionary says is wrong, and nothing
/// visibly fails. So the cache validates itself against the entries it was built from rather
/// than relying on every mutation site remembering to invalidate it. Passing different
/// entries rebuilds, always — there is no invalidation call to forget.
public struct CachedCorrector {
    private var builtFrom: [DictionaryEntry]?
    private var cached: DictionaryCorrector?

    public init() {}

    /// - Returns: a corrector for `entries`, reusing the previous one when they are identical.
    public mutating func corrector(for entries: [DictionaryEntry]) -> DictionaryCorrector {
        if let cached, builtFrom == entries { return cached }
        let corrector = DictionaryCorrector(entries: entries)
        builtFrom = entries
        cached = corrector
        return corrector
    }

    /// Whether the next call would rebuild. Exposed for tests — the difference between a hit
    /// and a miss is otherwise invisible except as timing, which is not something to assert.
    public func wouldRebuild(for entries: [DictionaryEntry]) -> Bool {
        cached == nil || builtFrom != entries
    }
}
