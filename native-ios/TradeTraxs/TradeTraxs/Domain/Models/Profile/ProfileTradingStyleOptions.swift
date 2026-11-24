import Foundation

/// Copy for `profiles.trading_style` (free text).
nonisolated enum ProfileTradingStyleField {
    static let label = "Trading Style / Strategy"
    static let placeholder = "e.g. scalping, Supply & Demand, ICT/SMC"
}

/// Copy for `profiles.trading_model`, searchable strategy tags (comma-separated).
nonisolated enum ProfileTradingModelField {
    static let label = "Strategies"
    static let placeholder = "e.g. ICT, SMC, Scalping, Breakout, Supply & Demand"
}

/// Copy for `profiles.primary_market` (free text), matches Settings → Profile.
nonisolated enum ProfilePrimaryMarketField {
    static let label = "Primary Ticker"
    static let placeholder = "e.g. NQ, ES"
}
