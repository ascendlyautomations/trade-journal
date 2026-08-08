import CoreGraphics
import SwiftUI

/// Canonical spacing scale. All layout insets/gaps use these tokens.
enum SpacingToken: CGFloat, CaseIterable, Sendable {
    case xxs = 4
    case xs = 8
    case sm = 12
    case md = 16
    case lg = 20
    case xl = 24
    case xxl = 32
    case xxxl = 40
    case huge = 48
    case massive = 64

    var value: CGFloat { rawValue }
}

enum ExperienceSpacing {
    static let xxs = SpacingToken.xxs.value
    static let xs = SpacingToken.xs.value
    static let sm = SpacingToken.sm.value
    static let md = SpacingToken.md.value
    static let lg = SpacingToken.lg.value
    static let xl = SpacingToken.xl.value
    static let xxl = SpacingToken.xxl.value
    static let xxxl = SpacingToken.xxxl.value
    static let huge = SpacingToken.huge.value
    static let massive = SpacingToken.massive.value

    /// Minimum comfortable touch target (HIG).
    static let minTouchTarget: CGFloat = 44
}

extension View {
    func experiencePadding(_ token: SpacingToken) -> some View {
        padding(token.value)
    }

    func experiencePadding(_ edges: Edge.Set, _ token: SpacingToken) -> some View {
        padding(edges, token.value)
    }
}
