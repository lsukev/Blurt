import Foundation
import Testing

@testable import BlurtSetup

@Suite("Setup flow")
struct SetupFlowTests {

    // MARK: - Navigation

    @Test("advancing walks every step in order and then finishes")
    func advancesThroughAllSteps() {
        var flow = SetupFlow()
        #expect(flow.step == .welcome)

        for expected in SetupStep.allCases.dropFirst() {
            flow.advance()
            #expect(flow.step == expected)
            #expect(!flow.isFinished)
        }

        // Off the end of the last step is a finish, not a trap — that's the button on the
        // final screen, and it has to work.
        flow.advance()
        #expect(flow.isFinished)
    }

    @Test("finishing is what skipping out of setup does, from any step")
    func skipFinishesFromAnywhere() {
        for step in SetupStep.allCases {
            var flow = SetupFlow(step: step)
            flow.finish()
            #expect(flow.isFinished, "skipping from \(step.title) should leave setup")
        }
    }

    // MARK: - Lamps

    @Test("a permission lamp reports the grant, never how far you have walked")
    func permissionLampsFollowGrantsNotPosition() {
        // Someone who skipped both permission steps and is now on the last one.
        let flow = SetupFlow(step: .done)

        #expect(!flow.isLampLit(for: .accessibility, accessibility: false, microphone: false),
                "skipping past Accessibility must not light its lamp")
        #expect(!flow.isLampLit(for: .microphone, accessibility: false, microphone: false),
                "skipping past Microphone must not light its lamp")

        // …and they light the moment the grant is real, wherever the user happens to be.
        let early = SetupFlow(step: .welcome)
        #expect(early.isLampLit(for: .accessibility, accessibility: true, microphone: false))
        #expect(early.isLampLit(for: .microphone, accessibility: false, microphone: true))
    }

    @Test("an ordinary step's lamp lights once it is behind you")
    func ordinaryLampsFollowPosition() {
        let flow = SetupFlow(step: .key)
        #expect(flow.isLampLit(for: .welcome, accessibility: false, microphone: false))
        #expect(!flow.isLampLit(for: .key, accessibility: false, microphone: false),
                "the step you are on is not yet done")
        #expect(!flow.isLampLit(for: .tryIt, accessibility: false, microphone: false))
    }

    // MARK: - Wedged-grant policy

    @Test("the reset is not offered before the user has been sent to Settings")
    func noResetWithoutAPrompt() {
        #expect(!SetupFlow.shouldOfferReset(
            promptedAt: nil,
            now: Date(timeIntervalSince1970: 10_000),
            isGranted: false,
            currentStep: .accessibility
        ))
    }

    @Test("the reset is not offered while the user is plausibly still doing it")
    func noResetBeforeTheThreshold() {
        let prompted = Date(timeIntervalSince1970: 10_000)
        #expect(!SetupFlow.shouldOfferReset(
            promptedAt: prompted,
            now: prompted.addingTimeInterval(24),
            isGranted: false,
            currentStep: .accessibility
        ))
    }

    @Test("the reset is offered once enough time has passed with no grant")
    func offersResetAfterThreshold() {
        let prompted = Date(timeIntervalSince1970: 10_000)
        #expect(SetupFlow.shouldOfferReset(
            promptedAt: prompted,
            now: prompted.addingTimeInterval(25),
            isGranted: false,
            currentStep: .accessibility
        ))
    }

    @Test("a granted permission never offers the reset, however long it took")
    func neverOffersResetOnceGranted() {
        let prompted = Date(timeIntervalSince1970: 10_000)
        #expect(!SetupFlow.shouldOfferReset(
            promptedAt: prompted,
            now: prompted.addingTimeInterval(10_000),
            isGranted: false,
            currentStep: .microphone
        ), "the offer belongs to the Accessibility step alone")

        #expect(!SetupFlow.shouldOfferReset(
            promptedAt: prompted,
            now: prompted.addingTimeInterval(10_000),
            isGranted: true,
            currentStep: .accessibility
        ))
    }

    @Test("leaving the Accessibility step withdraws the offer")
    func offerIsScopedToItsStep() {
        let prompted = Date(timeIntervalSince1970: 10_000)
        let late = prompted.addingTimeInterval(600)
        for step in SetupStep.allCases where step != .accessibility {
            #expect(!SetupFlow.shouldOfferReset(
                promptedAt: prompted,
                now: late,
                isGranted: false,
                currentStep: step
            ), "\(step.title) should not offer a TCC reset")
        }
    }
}
