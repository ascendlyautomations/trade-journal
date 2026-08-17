import SwiftUI

/// Social trade post detail — likes, comments, community discussion.
///
/// Opened from Feed / Profile / Explore / Activity. No Trade AI or journal tools.
struct SocialTradeDetailView: View {
    let tradeID: TradeID
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    var body: some View {
        TradeDetailView(
            tradeID: tradeID,
            data: data,
            navigationCoordinator: navigationCoordinator,
            experience: .social
        )
    }
}
