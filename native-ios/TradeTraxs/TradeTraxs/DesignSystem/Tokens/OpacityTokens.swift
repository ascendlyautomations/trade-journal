import CoreGraphics

enum OpacityToken: CGFloat, CaseIterable, Sendable {
    case invisible = 0
    case faint = 0.08
    case subtle = 0.16
    case muted = 0.4
    case secondary = 0.64
    case primary = 0.92
    case opaque = 1

    var value: CGFloat { rawValue }
}

enum ExperienceOpacity {
    static let invisible = OpacityToken.invisible.value
    static let faint = OpacityToken.faint.value
    static let subtle = OpacityToken.subtle.value
    static let muted = OpacityToken.muted.value
    static let secondary = OpacityToken.secondary.value
    static let primary = OpacityToken.primary.value
    static let opaque = OpacityToken.opaque.value

    static let disabled = muted
    static let pressed = secondary
    static let overlay = 0.45
}
