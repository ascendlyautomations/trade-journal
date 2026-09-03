import Foundation

@MainActor
enum GettingStartedTaskNavigation {
    static func open(
        task: GettingStartedTaskID,
        signals: GettingStartedSignals,
        coordinator: NavigationCoordinator
    ) {
        switch task {
        case .profile:
            coordinator.selectTab(.profile)
            coordinator.pushProfile(.settings(.profile))

        case .trade:
            coordinator.openCompose(.trade)

        case .follow:
            coordinator.selectTab(.feed)
            coordinator.pushFeed(.suggestedTraders)

        case .room:
            coordinator.selectTab(.feed)
            coordinator.pushFeed(.rooms)

        case .publicTrade:
            if let tradeID = signals.firstPrivateTradeID {
                coordinator.selectTab(.home)
                coordinator.editTrade(tradeID)
            } else {
                coordinator.selectTab(.home)
                coordinator.pushHome(.trades)
            }

        case .post:
            coordinator.openCompose(.post)
        }
    }
}
