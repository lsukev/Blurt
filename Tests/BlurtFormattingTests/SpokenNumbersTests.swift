import Testing

@testable import BlurtFormatting

@Suite("Spoken numbers")
struct SpokenNumbersTests {

    @Test("the reported case")
    func reportedCase() {
        // "2026 Data Center and Report" came back as "Twenty twenty six Data Center and
        // Report". The conjunction is the trap: swallowing it destroys the title.
        #expect(SpokenNumbers.digitize("twenty twenty six Data Center and Report")
                == "2026 Data Center and Report")
    }

    @Test("years spoken as two halves")
    func years() {
        #expect(SpokenNumbers.digitize("twenty twenty six") == "2026")
        #expect(SpokenNumbers.digitize("nineteen ninety nine") == "1999")
        #expect(SpokenNumbers.digitize("nineteen eighty four") == "1984")
        #expect(SpokenNumbers.digitize("twenty ten") == "2010")
        #expect(SpokenNumbers.digitize("nineteen oh five") == "1905")
    }

    @Test("years spoken the long way")
    func thousandsForm() {
        #expect(SpokenNumbers.digitize("two thousand twenty six") == "2026")
        #expect(SpokenNumbers.digitize("two thousand") == "2000")
    }

    @Test("ordinary numbers are not mistaken for years")
    func cardinals() {
        // "forty two" must be 42, not 4002 — a bare unit after a tens word continues it.
        #expect(SpokenNumbers.digitize("forty two") == "42")
        #expect(SpokenNumbers.digitize("twenty five") == "25")
        #expect(SpokenNumbers.digitize("one hundred twenty three") == "123")
        #expect(SpokenNumbers.digitize("three thousand") == "3000")
    }

    @Test("\"and\" joins a number but never a phrase")
    func andHandling() {
        #expect(SpokenNumbers.digitize("two hundred and five") == "205")
        // The one that matters: a conjunction between ordinary words is left alone.
        #expect(SpokenNumbers.digitize("Data Center and Report") == "Data Center and Report")
        #expect(SpokenNumbers.digitize("research and development") == "research and development")
    }

    @Test("small numbers stay as words")
    func smallNumbersUnchanged() {
        // "three people" reads better than "3 people"; years and quantities are all above
        // the threshold anyway.
        #expect(SpokenNumbers.digitize("three people") == "three people")
        #expect(SpokenNumbers.digitize("one") == "one")
        #expect(SpokenNumbers.digitize("nine lives") == "nine lives")
        #expect(SpokenNumbers.digitize("ten people") == "10 people")
    }

    @Test("text with no numbers is untouched")
    func noNumbers() {
        let s = "the quick brown fox jumps over the lazy dog"
        #expect(SpokenNumbers.digitize(s) == s)
    }

    @Test("punctuation rides along")
    func punctuation() {
        #expect(SpokenNumbers.digitize("in twenty twenty six, we shipped")
                == "in 2026, we shipped")
        #expect(SpokenNumbers.digitize("due by nineteen ninety nine.") == "due by 1999.")
    }

    @Test("a number does not run across a clause boundary")
    func clauseBoundaries() {
        // Without this, "twenty, thirty" reads as one span and becomes 2030.
        #expect(SpokenNumbers.digitize("twenty, thirty") == "20, 30")
    }

    @Test("numbers embedded in a sentence")
    func embedded() {
        #expect(SpokenNumbers.digitize("we hired forty two people in twenty twenty four")
                == "we hired 42 people in 2024")
    }

    @Test("case is ignored on the way in")
    func caseInsensitive() {
        #expect(SpokenNumbers.digitize("Twenty twenty six") == "2026")
    }
}

@Suite("Numbers through the whole pass")
struct NumbersInCleanupTests {

    @Test("the reported case, end to end in a name field")
    func nameField() {
        // What the user said, what the engine produced, what should land in the box.
        #expect(RuleCleanup.apply("twenty twenty six data center and report!", field: .singleLine)
                == "2026 Data Center and Report")
    }

    @Test("digits survive title casing")
    func digitsAreNotCased() {
        // TitleCase capitalizes the first *letter*; a token with none must pass through.
        #expect(RuleCleanup.apply("twenty twenty six annual review", field: .singleLine)
                == "2026 Annual Review")
    }

    @Test("prose gets digits too, and keeps its sentence shape")
    func prose() {
        #expect(RuleCleanup.apply("we shipped it in twenty twenty six", field: .multiLine)
                == "We shipped it in 2026")
    }

    @Test("the model is told the same rule")
    func modelAgrees() {
        // Otherwise the same phrase comes out two ways depending on whether Apple
        // Intelligence happens to be switched on.
        let text = CleanupInstructions.build(tone: .asSpoken)
        #expect(text.contains("2026"))
        #expect(text.lowercased().contains("digits"))
    }
}
