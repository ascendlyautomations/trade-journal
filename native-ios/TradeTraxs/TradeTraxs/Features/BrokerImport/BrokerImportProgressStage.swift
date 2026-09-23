import Foundation

/// Client-side stages mapped to real broker sync work (single HTTP request — no fake per-trade ticks).
nonisolated enum BrokerImportProgressStage: String, Sendable, Equatable, CaseIterable {
    case connecting
    case fetchingExecutions
    case processingTrades
    case savingTrades
    case finalizing

    var title: String {
        switch self {
        case .connecting: return "Connecting…"
        case .fetchingExecutions: return "Fetching executions…"
        case .processingTrades: return "Processing trades…"
        case .savingTrades: return "Saving trades…"
        case .finalizing: return "Finalizing…"
        }
    }

    /// Upper bound for indeterminate progress while awaiting the sync HTTP response.
    var indeterminateProgressCap: Double {
        switch self {
        case .connecting: return 0.12
        case .fetchingExecutions: return 0.38
        case .processingTrades: return 0.62
        case .savingTrades: return 0.82
        case .finalizing: return 0.92
        }
    }
}
