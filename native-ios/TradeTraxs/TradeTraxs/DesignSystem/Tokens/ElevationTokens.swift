import CoreGraphics
import SwiftUI

/// Soft elevation language — prefer materials over heavy multi-shadow stacks.
enum ElevationToken: Int, CaseIterable, Sendable {
    case flat = 0
    case low = 1
    case medium = 2
    case high = 3

    var radius: CGFloat {
        switch self {
        case .flat: return 0
        case .low: return 4
        case .medium: return 10
        case .high: return 18
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .flat: return 0
        case .low: return 1
        case .medium: return 4
        case .high: return 8
        }
    }

    var opacity: Double {
        switch self {
        case .flat: return 0
        case .low: return 0.08
        case .medium: return 0.12
        case .high: return 0.18
        }
    }
}

struct ExperienceElevationModifier: ViewModifier {
    let token: ElevationToken
    let shadowColor: Color

    func body(content: Content) -> some View {
        content.shadow(
            color: shadowColor.opacity(token.opacity),
            radius: token.radius,
            x: 0,
            y: token.yOffset
        )
    }
}

extension View {
    func experienceElevation(
        _ token: ElevationToken,
        shadowColor: Color = .black
    ) -> some View {
        modifier(ExperienceElevationModifier(token: token, shadowColor: shadowColor))
    }
}
