import Foundation

/// TradeTraxs AI copy style — user-facing LLM prose only (not user-authored content).
///
/// See `lib/aiCopyStyle.md` and `lib/normalizeAIGeneratedText.ts` (web SoT).
nonisolated enum AIGeneratedTextNormalizer {
    static func normalize(_ text: String) -> String {
        GeneratedProseNormalizer.normalize(text)
    }
}
