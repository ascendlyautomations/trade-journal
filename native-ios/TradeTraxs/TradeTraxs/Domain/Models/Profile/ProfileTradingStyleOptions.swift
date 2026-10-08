import Foundation

/// Copy for `profiles.trading_style` (free text).
nonisolated enum ProfileTradingStyleField {
    static let label = "Trading Style / Strategy"
    static let placeholder = "e.g. scalping, Supply & Demand, ICT/SMC"
}

/// Copy for `profiles.primary_market` (free text) — matches Settings → Profile.
nonisolated enum ProfilePrimaryMarketField {
    static let label = "Primary Market"
    static let placeholder = "e.g. Futures, Options"
}
