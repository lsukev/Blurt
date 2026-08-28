import Testing

@testable import BlurtDictionary

@Suite("Cached corrector")
struct CachedCorrectorTests {

    private func rule(_ hear: String, _ write: String) -> DictionaryEntry {
        DictionaryEntry(kind: .correction, write: write, hear: hear)
    }

    @Test("the same entries reuse the built corrector")
    func hitsOnIdenticalEntries() {
        var cache = CachedCorrector()
        let entries = [rule("cloud code", "Claude Code")]
        #expect(cache.wouldRebuild(for: entries))
        _ = cache.corrector(for: entries)
        #expect(!cache.wouldRebuild(for: entries), "an unchanged dictionary must not recompile")
    }

    // The reason caching was resisted: a corrector outliving an edit produces text the
    // user's own dictionary says is wrong, and nothing visibly fails. Each mutation shape
    // gets its own test rather than trusting one to cover the rest.

    @Test("adding an entry rebuilds, and the new rule fires")
    func addingAnEntryInvalidates() {
        var cache = CachedCorrector()
        var entries = [rule("cloud code", "Claude Code")]
        #expect(cache.corrector(for: entries).apply(to: "the cloud code team").0 == "the Claude Code team")

        entries.append(rule("anthropic", "Anthropic"))
        #expect(cache.wouldRebuild(for: entries))
        #expect(cache.corrector(for: entries).apply(to: "anthropic ships").0 == "Anthropic ships")
    }

    @Test("removing an entry rebuilds, and the old rule stops firing")
    func removingAnEntryInvalidates() {
        var cache = CachedCorrector()
        let full = [rule("cloud code", "Claude Code"), rule("anthropic", "Anthropic")]
        #expect(cache.corrector(for: full).apply(to: "anthropic ships").0 == "Anthropic ships")

        let reduced = [full[0]]
        #expect(cache.wouldRebuild(for: reduced))
        #expect(cache.corrector(for: reduced).apply(to: "anthropic ships").0 == "anthropic ships",
                "a deleted rule must stop applying")
    }

    @Test("editing an entry in place rebuilds")
    func editingAnEntryInvalidates() {
        var cache = CachedCorrector()
        var entries = [rule("cloud code", "Claude Code")]
        _ = cache.corrector(for: entries)

        entries[0].write = "Claude Codex"
        #expect(cache.wouldRebuild(for: entries), "an edited replacement must not be served stale")
        #expect(cache.corrector(for: entries).apply(to: "cloud code").0 == "Claude Codex")
    }

    @Test("disabling an entry rebuilds and stops the rule")
    func disablingAnEntryInvalidates() {
        var cache = CachedCorrector()
        var entries = [rule("cloud code", "Claude Code")]
        _ = cache.corrector(for: entries)

        entries[0].isEnabled = false
        #expect(cache.wouldRebuild(for: entries))
        #expect(cache.corrector(for: entries).apply(to: "cloud code").0 == "cloud code")
    }

    @Test("reordering rebuilds, because order decides which rule wins")
    func reorderingInvalidates() {
        // Longest-trigger-first is what makes "Claude Code" beat "Claude"; a cache that
        // ignored order could serve a corrector built from a different precedence.
        var cache = CachedCorrector()
        let entries = [rule("cloud code", "Claude Code"), rule("cloud", "Cloud")]
        _ = cache.corrector(for: entries)
        #expect(cache.wouldRebuild(for: entries.reversed().map { $0 }))
    }

    @Test("an empty dictionary is cached too")
    func emptyIsCached() {
        var cache = CachedCorrector()
        _ = cache.corrector(for: [])
        #expect(!cache.wouldRebuild(for: []), "an empty dictionary should not recompile either")
    }
}
