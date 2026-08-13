import Foundation

/// Snapshot of the Reports catalog screen — single source of truth.
struct ReportsState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .idle
    var cards: [ReportTypeCardModel] = []
    var snapshot: TradingReportsSnapshot?
    var generatingPeriod: TradingReportPeriodKey?
    var isRefreshing = false
    var didBootstrap = false
    var lastUpdated: Date?

    var showsEmpty: Bool {
        phase == .loaded && cards.isEmpty
    }
}

extension ReportsState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var pagination: ScreenPaginationSnapshot { .none }
}

/// Snapshot for Report Detail.
struct ReportDetailState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Resolved Best Trade reference — never exposes raw IDs in the UI.
    enum BestTradeReference: Equatable {
        case loading
        case available(Trade)
        case unavailable
    }

    var phase: Phase = .idle
    var periodKey: TradingReportPeriodKey?
    var report: TradingReport?
    var blocks: [TradingReportDetailBlock] = []
    var bestTrade: BestTradeReference?
    var didBootstrap = false
    var isRefreshing = false
    var lastUpdated: Date?
    var errorMessage: String?
}

extension ReportDetailState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return errorMessage
    }

    var pagination: ScreenPaginationSnapshot { .none }
}
