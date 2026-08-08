import CoreGraphics
import SwiftUI

enum RadiusToken: CGFloat, CaseIterable, Sendable {
    case none = 0
    case xs = 6
    case sm = 10
    case md = 14
    case lg = 18
    case xl = 24
    case full = 999

    var value: CGFloat { rawValue }
}

enum ExperienceRadius {
    static let none = RadiusToken.none.value
    static let xs = RadiusToken.xs.value
    static let sm = RadiusToken.sm.value
    static let md = RadiusToken.md.value
    static let lg = RadiusToken.lg.value
    static let xl = RadiusToken.xl.value
    static let full = RadiusToken.full.value

    static let button = md
    static let card = lg
    static let chip = full
    static let sheet = xl
}
