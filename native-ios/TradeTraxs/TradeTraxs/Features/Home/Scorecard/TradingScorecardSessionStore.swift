import Foundation
import Observation

/// Shared scorecard snapshot between Dashboard home and detail — no extra network.
@MainActor
@Observable
final class TradingScorecardSessionStore {
    static let shared = TradingScorecardSessionStore()

    private(set) var ready = false
    private(set) var result: ScorecardResult?
    private(set) var highlights: TradingScorecardBuilder.Highlights = .init(strengths: [], weaknesses: [])
    /// Early psychology cards for detail visuals (same builder as dashboard psych section).
    private(set) var psychologyInsightCards: [PsychologyInsightCard] = []

    private init() {}

    func publish(
        ready: Bool,
        result: ScorecardResult?,
        highlights: TradingScorecardBuilder.Highlights,
        psychologyInsightCards: [PsychologyInsightCard] = []
    ) {
        self.ready = ready
        self.result = result
        self.highlights = highlights
        self.psychologyInsightCards = psychologyInsightCards
    }

    func reset() {
        ready = false
        result = nil
        highlights = .init(strengths: [], weaknesses: [])
        psychologyInsightCards = []
    }
}
