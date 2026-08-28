import Testing

@testable import BlurtFormatting

@Suite("Cleanup routing")
struct CleanupRoutingTests {

    private func needs(_ text: String, tone: ToneMode = .asSpoken, field: FieldKind = .unknown) -> Bool {
        CleanupRouting.needsModel(text, tone: tone, field: field)
    }

    // The whole point: skipping the model must not cost anything the rules cannot do.

    @Test("a short self-correction still goes to the model")
    func shortCorrectionsStillNeedTheModel() {
        // Five words. The naive "skip short utterances" rule would drop this, and no regex
        // can work out which part of the sentence is being replaced.
        #expect(needs("send it Tuesday, actually Wednesday"))
        #expect(needs("meet at three, I mean four"))
        #expect(needs("call Bob, no wait, call Susan"))
        #expect(needs("make that two copies"))
    }

    @Test("ambiguous fillers go to the model, because rules refuse to touch them")
    func ambiguousFillersNeedTheModel() {
        #expect(needs("it was like fine"))
        #expect(needs("that's you know the plan"))
        #expect(needs("basically done"))
    }

    @Test("an ambiguous filler inside another word does not count")
    func fillerWordBoundaries() {
        // "like" hides in "likely" and "unlike"; matching loosely would send everything
        // to the model and undo the optimization.
        #expect(!needs("a likely outcome"))
        #expect(!needs("unlike the others"))
    }

    @Test("a short plain label skips the model")
    func shortLabelsSkipTheModel() {
        #expect(!needs("2026 Data Center and Report"))
        #expect(!needs("on my way"))
        #expect(!needs("quarterly budget review"))
    }

    @Test("longer prose goes to the model")
    func longProseNeedsTheModel() {
        let long = "we should ship the disaster recovery report before the end of the quarter "
            + "and then follow up with the compliance team about the outstanding findings"
        #expect(needs(long))
    }

    @Test("Casual and Formal always use the model")
    func rewritingTonesAlwaysNeedTheModel() {
        // These modes exist to rewrite. The rule pass cannot rewrite anything, so skipping
        // would silently ignore the setting the user chose.
        #expect(needs("on my way", tone: .casual))
        #expect(needs("on my way", tone: .formal))
        #expect(!needs("on my way", tone: .asSpoken))
    }

    @Test("empty input does not need the model")
    func emptyInput() {
        #expect(!needs(""))
    }
}
