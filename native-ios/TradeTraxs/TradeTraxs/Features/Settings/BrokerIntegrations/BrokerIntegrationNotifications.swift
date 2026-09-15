import Foundation

extension Notification.Name {
    static let tradovateBrokerOAuthCompleted = Notification.Name("tradovateBrokerOAuthCompleted")
}

enum TradovateBrokerOAuthNotificationPayload {
    static let statusKey = "status"
    static let reasonKey = "reason"

    static func post(from url: URL) {
        guard NativeOAuthConfiguration.isTradovateBrokerOAuthCallbackURL(url) else { return }
        let items = NativeOAuthConfiguration.fragmentOrQueryItems(from: url)
        NotificationCenter.default.post(
            name: .tradovateBrokerOAuthCompleted,
            object: nil,
            userInfo: [
                statusKey: items["status"] ?? "",
                reasonKey: items["reason"] ?? "",
            ]
        )
    }
}
