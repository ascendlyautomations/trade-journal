import Foundation

/// Session-scoped psychology coach state — deterministic facts always; AI summaries cached by hash.
@MainActor
final class PsychologyCoachSessionStore {
    static let shared = PsychologyCoachSessionStore()

    private(set) var facts: PsychologyCoachFacts?
    private(set) var deterministicSummary: PsychologyCoachSummary?
    private(set) var cachedAIExplanation: String?
    private(set) var cachedAIHash: String?
    private(set) var aiStale = false

    private init() {}

    func update(
        facts: PsychologyCoachFacts,
        summary: PsychologyCoachSummary
    ) {
        self.facts = facts
        deterministicSummary = summary
        if cachedAIHash != facts.factsHash {
            aiStale = cachedAIHash != nil
        }
    }

    func applyCachedAI(explanation: String, factsHash: String) {
        cachedAIExplanation = explanation
        cachedAIHash = factsHash
        aiStale = false
    }

    func clearAICache() {
        cachedAIExplanation = nil
        cachedAIHash = nil
        aiStale = false
    }

    func invalidate() {
        facts = nil
        deterministicSummary = nil
        clearAICache()
    }
}
