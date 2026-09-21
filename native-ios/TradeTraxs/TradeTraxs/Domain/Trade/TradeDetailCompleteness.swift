import Foundation

/// Marks whether a cached `Trade` may be treated as authoritative detail.
nonisolated enum TradeDetailAuthority: Sendable, Equatable {
    case listSeed
    case authoritativeNetwork
    case authoritativeMutation
}

nonisolated enum TradeDetailCompleteness {
    /// List/bootstrap seeds and partial wire rows must not satisfy edit/detail completeness.
    static func isAuthoritative(_ authority: TradeDetailAuthority) -> Bool {
        switch authority {
        case .listSeed:
            return false
        case .authoritativeNetwork, .authoritativeMutation:
            return true
        }
    }

    /// Detail fetch uses `ownerJournalSelect` — includes psychology + import columns when present on wire.
    static func detailSelectIncludesJournalFields(_ select: String) -> Bool {
        select.contains("psychology_notes")
            && select.contains("exit_emotion")
            && select.contains("execution_rating")
            && select.contains("import_source")
            && select.contains("import_fingerprint")
    }
}
