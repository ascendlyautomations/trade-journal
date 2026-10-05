import Foundation

/// Presentation mode for trade detail — journal vs social community.
///
/// Business loading stays in ``TradeDetailViewModel``; only UI differs.
enum TradeDetailExperience: Hashable, Sendable {
    /// Dashboard / Calendar / History / Reports — AI, notes, trade management.
    case journal
    /// Feed / Profile / Explore / Activity — likes, comments, community.
    case social
}

/// Social detail metrics layout — Profile uses two-row execution grid above engagement.
enum TradeDetailSocialLayout: Hashable, Sendable {
    case standard
    case profile
}
