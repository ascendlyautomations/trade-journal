import UIKit

/// Centralized haptics. Features call this API — never UIKit generators directly.
enum HapticEvent: String, Sendable {
    case selection
    case success
    case warning
    case error
    case tradeSaved
    case messageSent
    case notification
    case achievement
    case impactLight
    case impactMedium
    case impactHeavy
}

enum ExperienceHaptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    static func prepare(_ event: HapticEvent = .selection) {
        switch event {
        case .selection:
            selection.prepare()
        case .success, .warning, .error, .tradeSaved, .messageSent, .notification, .achievement:
            notification.prepare()
        case .impactLight:
            light.prepare()
        case .impactMedium:
            medium.prepare()
        case .impactHeavy:
            heavy.prepare()
        }
    }

    static func play(_ event: HapticEvent) {
        switch event {
        case .selection:
            selection.selectionChanged()
        case .success, .tradeSaved, .messageSent, .achievement:
            notification.notificationOccurred(.success)
        case .warning, .notification:
            notification.notificationOccurred(.warning)
        case .error:
            notification.notificationOccurred(.error)
        case .impactLight:
            light.impactOccurred()
        case .impactMedium:
            medium.impactOccurred()
        case .impactHeavy:
            heavy.impactOccurred()
        }
    }
}
