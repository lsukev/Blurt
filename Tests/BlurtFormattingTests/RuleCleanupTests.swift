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

@Suite("Single-line fields")
struct SingleLineFieldTests {

    // A one-line field holds a label. The reported case: dictating a document title into a
    // Name box produced "Disaster recovery test report." — sentence case, and a full stop
    // that came from the speech engine rather than from us, so the earlier fix missed it.

    @Test("the reported case")
    func documentTitleInANameField() {
        #expect(RuleCleanup.apply("disaster recovery test report.", field: .singleLine)
                == "Disaster Recovery Test Report")
    }

    @Test("a stop the engine supplied is removed, not just one we would have added")
    func stripsEngineSuppliedStop() {
        // This is the whole point: cleanup already never appends. Preserving what the engine
        // sent is right for prose and wrong for a label.
        #expect(RuleCleanup.apply("Quarterly review.", field: .singleLine) == "Quarterly Review")
        #expect(RuleCleanup.apply("Quarterly review.", field: .multiLine) == "Quarterly review.")
    }

    @Test("question and exclamation marks stay")
    func keepsMeaningfulPunctuation() {
        // Nobody means a trailing stop in a name box; someone typing a question does.
        #expect(RuleCleanup.apply("is this right?", field: .singleLine) == "Is This Right?")
    }

    @Test("minor words stay lowercase, but never first or last")
    func minorWords() {
        #expect(RuleCleanup.apply("the state of the union", field: .singleLine)
                == "The State of the Union")
        #expect(RuleCleanup.apply("something to look at", field: .singleLine)
                == "Something to Look At")
    }

    @Test("deliberate capitalization survives")
    func preservesInteriorCapitals() {
        // "PDF" and "iPhone" are spellings, not sentence case to be normalized.
        #expect(RuleCleanup.apply("export as PDF", field: .singleLine) == "Export as PDF")
        #expect(RuleCleanup.apply("my iPhone backup", field: .singleLine) == "My iPhone Backup")
    }

    @Test("addresses and paths are left alone entirely")
    func doesNotManglIdentifiers() {
        // The risk accepted when title casing became automatic — bounded here rather than
        // left to chance.
        #expect(RuleCleanup.apply("kevin@example.com", field: .singleLine) == "kevin@example.com")
        #expect(RuleCleanup.apply("reports/2025/q4.pdf", field: .singleLine) == "reports/2025/q4.pdf")
    }

    @Test("an unknown target behaves exactly as before")
    func unknownIsUnchanged() {
        // An app with a surprising accessibility tree must lose nothing, not gain surprises.
        for text in ["disaster recovery test report.", "what time is it", "yeah"] {
            #expect(RuleCleanup.apply(text, field: .unknown) == RuleCleanup.apply(text))
        }
    }

    @Test("an abbreviation keeps its stop")
    func abbreviationsKeepTheirStop() {
        #expect(RuleCleanup.apply("policies for the U.S.", field: .singleLine).hasSuffix("U.S."))
    }
}

@Suite("Abbreviations in a single-line field")
struct AbbreviationTests {

    // Stripping the terminal stop must not amputate an abbreviation. Three separate
    // detections, because none of them covers the others.

    @Test("an interior period marks an abbreviation")
    func interiorPeriod() {
        #expect(RuleCleanup.apply("policies for the U.S.", field: .singleLine) == "Policies for the U.S.")
        #expect(RuleCleanup.apply("meeting at 9 a.m.", field: .singleLine).hasSuffix("a.m."))
    }

    @Test("a lone initial keeps its stop")
    func initials() {
        #expect(RuleCleanup.apply("notes from Kevin L.", field: .singleLine).hasSuffix("Kevin L."))
    }

    @Test("known abbreviations keep their stop")
    func knownAbbreviations() {
        // Structurally identical to "report." — only a list can tell them apart.
        #expect(RuleCleanup.apply("budget travel etc.", field: .singleLine).hasSuffix("etc."))
        #expect(RuleCleanup.apply("invoice for Acme Inc.", field: .singleLine).hasSuffix("Inc."))
    }

    @Test("an ordinary word still loses its stop")
    func ordinaryWordsAreStripped() {
        #expect(RuleCleanup.apply("disaster recovery test report.", field: .singleLine)
                == "Disaster Recovery Test Report")
    }
}

@Suite("Terminal punctuation in a label")
struct LabelPunctuationTests {

    // Reported: dictating "2026 Data Center and Report" into a Name box produced an
    // exclamation mark nobody spoke. The engine adds those from intonation.

    @Test("an exclamation mark is stripped from a label")
    func stripsExclamation() {
        #expect(RuleCleanup.apply("data center report!", field: .singleLine) == "Data Center Report")
    }

    @Test("a question mark survives, because the engine emits those from structure")
    func keepsQuestionMark() {
        #expect(RuleCleanup.apply("are you coming?", field: .singleLine) == "Are You Coming?")
    }

    @Test("prose keeps both, whoever supplied them")
    func proseIsUntouched() {
        #expect(RuleCleanup.apply("That's great!", field: .multiLine) == "That's great!")
        #expect(RuleCleanup.apply("Really?", field: .multiLine) == "Really?")
    }

    @Test("an abbreviation still keeps its stop")
    func abbreviationsUnaffected() {
        #expect(RuleCleanup.apply("figures for the U.S.", field: .singleLine).hasSuffix("U.S."))
    }
}
