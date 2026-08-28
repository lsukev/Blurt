import BlurtFormatting
import Foundation

/// The cleanup pass between raw transcription and injection.
///
/// This is where Wispr Flow actually earns its keep — raw STT output is full of filler
/// words, missing punctuation, and spoken corrections. Swapping in an LLM-backed
/// formatter (Apple Foundation Models on-device, or Claude for the high-quality tier)
/// is the point of keeping this behind a protocol.
protocol TextFormatter: Sendable {
    func format(_ raw: String, field: FieldKind) async -> String
}

/// Deterministic, zero-latency cleanup. Always the fallback when a model-backed formatter
/// is unavailable or times out — and on a Mac without Apple Intelligence, the only cleanup
/// that ever runs.
///
/// The logic lives in `BlurtFormatting.RuleCleanup` so it can be tested. It was untested
/// while it lived here, which is how it shipped appending a full stop to every one-word
/// answer and a full stop to every question.
struct RuleBasedFormatter: TextFormatter {
    func format(_ raw: String, field: FieldKind) async -> String {
        RuleCleanup.apply(raw, field: field)
    }
}

/// No-op formatter, for comparing raw engine output against the cleanup pass.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String, field: FieldKind) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
