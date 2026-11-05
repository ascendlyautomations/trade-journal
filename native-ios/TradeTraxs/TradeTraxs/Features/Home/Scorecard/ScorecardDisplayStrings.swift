import Foundation

nonisolated enum ScorecardDisplayStrings {
    static let planAdherenceScoreLabel = "Plan-Adherence Score (Phase 1)"
    static let phase1ScoreExplainer =
        "Phase 1 numbers come from explicit plan-adherence tags only. Consistency scores post-loss plan adherence; Discipline scores overall plan adherence among tagged trades. Risk Management and Psychology are informational in Phase 1, they do not affect this composite."

    static func categoryPhase1RowLabel(category: ScorecardCategoryResult) -> String {
        switch category.id {
        case .risk: return "Metrics only (Phase 1)"
        case .psychology: return "Insights only (Phase 1)"
        default:
            if let score = category.score { return String(score) }
            return "—"
        }
    }

    static func categoryPhase1DetailScoreLabel(category: ScorecardCategoryResult) -> String {
        switch category.id {
        case .risk: return "Metrics only (Phase 1)"
        case .psychology: return "Insights only (Phase 1)"
        default:
            if let score = category.score { return "\(score)/100" }
            return "Insufficient evidence"
        }
    }
}
