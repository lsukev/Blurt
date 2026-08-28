import Foundation
import FoundationModels

/// Owns the on-device model session, and warms it while the user is still talking.
///
/// Measured on a real dictation before this existed:
///
///     latency 3533ms · engine 173ms · cleanup 3332ms · dictionary 0ms · inject 27ms
///
/// Cleanup was 94% of the wait. A fresh `LanguageModelSession` was built for every
/// utterance, so the model prefilled the whole instruction block — base rules, tone, number
/// handling, and up to sixty dictionary terms — from cold, every time, *after* the user had
/// stopped speaking and was waiting.
///
/// Everything those instructions depend on is known the moment the key goes down: the tone,
/// the dictionary, and the field being dictated into. And what follows is seconds of
/// someone talking. So the session is built and prewarmed then, and by the time they let go
/// the prefill has already happened.
///
/// The session is consumed rather than kept. `LanguageModelSession` accumulates a
/// transcript across calls, so reusing one would grow the context with every dictation —
/// slower and eventually confused. One session per utterance, warmed early, then discarded.
actor CleanupModel {
    static let shared = CleanupModel()

    private var prepared: LanguageModelSession?
    private var preparedFor: String?

    /// Builds the session for the utterance about to be spoken and starts warming it.
    /// Cheap to call and safe to call repeatedly; a second call for the same instructions
    /// keeps the warming already under way.
    func prepare(instructions: String) {
        guard preparedFor != instructions else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        prepared = session
        preparedFor = instructions
    }

    /// Runs the cleanup, using the prewarmed session when it matches.
    ///
    /// The session stays inside this actor — it is a reference type shared with the model
    /// runtime, and handing it across isolation to be called elsewhere is exactly the kind
    /// of sharing an actor exists to prevent.
    func respond(
        instructions: String,
        prompt: String,
        options: GenerationOptions
    ) async throws -> String {
        let session: LanguageModelSession
        if let prepared, preparedFor == instructions {
            session = prepared
        } else {
            // Prewarming missed — a rebind mid-utterance, or cleanup switched on between
            // the key going down and coming up. Correct, just not warm.
            session = LanguageModelSession(instructions: instructions)
        }
        prepared = nil
        preparedFor = nil

        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
