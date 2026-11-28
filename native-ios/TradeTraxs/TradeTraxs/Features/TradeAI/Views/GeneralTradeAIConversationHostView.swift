import SwiftUI

/// Deep link host for a persisted general Trade AI thread (Messages inbox).
struct GeneralTradeAIConversationHostView: View {
    let conversationID: AIConversationID
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    var body: some View {
        GeneralTradeAICoachView(
            data: data,
            navigationCoordinator: navigationCoordinator,
            initialConversationID: conversationID
        )
    }
}