import SwiftUI

/// Personal trading journal detail — AI, notes, metrics, edit/delete.
///
/// Opened from Dashboard-owned paths (Home trades, Calendar, Reports, deep links).
struct JournalTradeDetailView: View {
    let tradeID: TradeID
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    var body: some View {
        TradeDetailView(
            tradeID: tradeID,
            data: data,
            navigationCoordinator: navigationCoordinator,
            experience: .journal
        )
    }
}
