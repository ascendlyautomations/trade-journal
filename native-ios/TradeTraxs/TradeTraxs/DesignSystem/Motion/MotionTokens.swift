import SwiftUI

/// Central motion language. Always gate decorative motion with Reduce Motion.
enum MotionDuration: Double, Sendable {
    case instant = 0.12
    case fast = 0.18
    case standard = 0.28
    case deliberate = 0.4
    case slow = 0.55

    var value: Double { rawValue }
}

enum MotionSpring: Sendable {
    case snappy
    case standard
    case gentle
    case bouncy

    var animation: Animation {
        switch self {
        case .snappy:
            return .spring(response: 0.28, dampingFraction: 0.86)
        case .standard:
            return .spring(response: 0.38, dampingFraction: 0.86)
        case .gentle:
            return .spring(response: 0.5, dampingFraction: 0.9)
        case .bouncy:
            return .spring(response: 0.42, dampingFraction: 0.72)
        }
    }
}

enum MotionCurve: Sendable {
    case easeIn
    case easeOut
    case easeInOut
    case linear

    func animation(duration: MotionDuration) -> Animation {
        switch self {
        case .easeIn: return .easeIn(duration: duration.value)
        case .easeOut: return .easeOut(duration: duration.value)
        case .easeInOut: return .easeInOut(duration: duration.value)
        case .linear: return .linear(duration: duration.value)
        }
    }
}

enum ExperienceMotion {
    static let navigation = MotionSpring.standard.animation
    static let modalPresent = MotionSpring.gentle.animation
    static let modalDismiss = MotionCurve.easeIn.animation(duration: .fast)
    static let loading = MotionCurve.linear.animation(duration: .slow).repeatForever(autoreverses: false)
    static let success = MotionSpring.snappy.animation
    static let selection = MotionCurve.easeOut.animation(duration: .instant)
    static let tabSwitch = MotionCurve.easeOut.animation(duration: .instant)

    /// Returns `animation` unless Reduce Motion is enabled.
    static func preferred(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func withAnimation(
        _ animation: Animation = ExperienceMotion.navigation,
        reduceMotion: Bool,
        _ body: () -> Void
    ) {
        if reduceMotion {
            body()
        } else {
            SwiftUI.withAnimation(animation, body)
        }
    }
}
