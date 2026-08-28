import Testing

@testable import BlurtFormatting

@Suite("Rule cleanup")
struct RuleCleanupTests {

    // MARK: - Terminal punctuation
    //
    // The reported bug: a full stop was appended to everything ending in a letter or digit.
    // This pass runs after the speech engine, and Apple's recognizer punctuates what it
    // hears as a sentence — so arriving here unpunctuated means the engine read a fragment.
    // Appending a stop overrode that judgement exactly where it was most likely right.

    @Test("a one-word answer gets no full stop")
    func singleWordsAreLeftAlone() {
        #expect(RuleCleanup.apply("yeah") == "Yeah")
        #expect(RuleCleanup.apply("Kevin") == "Kevin")
        #expect(RuleCleanup.apply("blue") == "Blue")
    }

    @Test("a chat-length fragment gets no full stop")
    func fragmentsAreLeftAlone() {
        #expect(RuleCleanup.apply("on my way") == "On my way")
        #expect(RuleCleanup.apply("sounds good to me") == "Sounds good to me")
    }

    @Test("punctuation the engine supplied is preserved")
    func existingPunctuationSurvives() {
        #expect(RuleCleanup.apply("I'll be there soon.") == "I'll be there soon.")
        #expect(RuleCleanup.apply("Really!") == "Really!")
        #expect(RuleCleanup.apply("Are you sure?") == "Are you sure?")
    }

    @Test("a question the engine left flat gets its mark")
    func questionsGetAQuestionMark() {
        #expect(RuleCleanup.apply("what time is it") == "What time is it?")
        #expect(RuleCleanup.apply("where are we meeting") == "Where are we meeting?")
        #expect(RuleCleanup.apply("can you send it over") == "Can you send it over?")
        #expect(RuleCleanup.apply("did they reply yet") == "Did they reply yet?")
    }

    @Test("an imperative starting with an auxiliary is not a question")
    func imperativesAreNotQuestions() {
        // The trap in auxiliary-initial detection: these open like questions and aren't.
        #expect(RuleCleanup.apply("have a good day") == "Have a good day")
        #expect(RuleCleanup.apply("do your best") == "Do your best")
        #expect(RuleCleanup.apply("will do") == "Will do")
    }

    @Test("wh-words that aren't asking anything are not questions")
    func whPhrasesThatAreNotQuestions() {
        #expect(RuleCleanup.apply("how to fix the build") == "How to fix the build")
        #expect(RuleCleanup.apply("what a mess") == "What a mess")
    }

    @Test("only the final clause decides")
    func questionDetectionUsesTheLastClause() {
        #expect(RuleCleanup.apply("I'm done. what time is it") == "I'm done. What time is it?")
        // ...and a statement after a question does not inherit the mark.
        #expect(RuleCleanup.apply("Where is it? I looked everywhere") == "Where is it? I looked everywhere")
    }

    @Test("a bare question word is not treated as a question")
    func loneQuestionWordIsNotAQuestion() {
        #expect(RuleCleanup.apply("what") == "What")
    }

    // MARK: - The passes that already worked

    @Test("standalone fillers are stripped")
    func fillersAreRemoved() {
        #expect(RuleCleanup.apply("um I think so") == "I think so")
        #expect(RuleCleanup.apply("so uh, that's the plan.") == "So that's the plan.")
    }

    @Test("a filler inside a real word survives")
    func fillersDoNotEatRealWords() {
        // "um" is inside both of these; a careless pattern would gut them.
        #expect(RuleCleanup.apply("the album") == "The album")
        #expect(RuleCleanup.apply("humming") == "Humming")
    }

    @Test("spoken punctuation becomes real breaks")
    func spokenPunctuation() {
        #expect(RuleCleanup.apply("first line new line second line").contains("\n"))
        #expect(RuleCleanup.apply("one new paragraph two").contains("\n\n"))
    }

    @Test("the first letter is capitalized, and so is the one after a stop")
    func capitalization() {
        #expect(RuleCleanup.apply("hello there. how are you") == "Hello there. How are you?")
    }

    @Test("whitespace collapses and spaces before punctuation close up")
    func whitespace() {
        #expect(RuleCleanup.apply("too   many    spaces here") == "Too many spaces here")
        #expect(RuleCleanup.apply("hold on , let me check") == "Hold on, let me check")
    }

    @Test("a question introduced by a comma clause is missed, deliberately")
    func commaClausesAreNotSplit() {
        // "Wait, what is that" is a question and gets no mark. Splitting clauses on commas
        // would catch it, and would also start marking "I wonder, what if we tried" and
        // similar musings. The complaint that prompted this work was too many spurious
        // marks, so the miss is the safer error. Recorded as a decision, not an accident.
        #expect(RuleCleanup.apply("wait, what is that") == "Wait, what is that")
    }

    @Test("empty and whitespace-only input stays empty")
    func emptyInput() {
        #expect(RuleCleanup.apply("") == "")
        #expect(RuleCleanup.apply("   \n  ") == "")
    }
}
