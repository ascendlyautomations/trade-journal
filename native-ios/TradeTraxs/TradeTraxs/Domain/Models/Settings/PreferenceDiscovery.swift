import Foundation

nonisolated enum PreferenceDiscoveryResponse: String, Codable, Sendable {
    case completed
    case skipped
    case dismissed

    var rank: Int {
        switch self {
        case .skipped: return 1
        case .dismissed: return 2
        case .completed: return 3
        }
    }
}

nonisolated enum PreferenceDiscoveryPlacement: Equatable, Sendable {
    /// One-time invitation after the walkthrough and the first saved trade.
    case firstTrade
    /// Small invitation on analytics and reports, and the dashboard card.
    case quiet
}

nonisolated enum PreferenceDiscoveryDecision {
    /// A saved preferences row counts as configured even when every optional field is blank.
    static func placement(
        configured: Bool,
        response: PreferenceDiscoveryResponse?,
        tourEligible: Bool,
        tourSettled: Bool,
        tourBlocking: Bool,
        hasTrade: Bool
    ) -> PreferenceDiscoveryPlacement? {
        if configured || response == .completed || response == .dismissed { return nil }
        if tourBlocking { return nil }
        let firstTradeReady = tourEligible && tourSettled && hasTrade && response == nil
        if firstTradeReady { return .firstTrade }
        if tourEligible && response == nil { return nil }
        if response == .skipped || !tourEligible { return .quiet }
        return nil
    }
}
