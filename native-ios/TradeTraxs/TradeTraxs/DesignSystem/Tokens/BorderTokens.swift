import CoreGraphics

enum BorderWidthToken: CGFloat, CaseIterable, Sendable {
    case none = 0
    case hairline = 0.5
    case thin = 1
    case thick = 2

    var value: CGFloat { rawValue }
}

enum ExperienceBorder {
    static let none = BorderWidthToken.none.value
    static let hairline = BorderWidthToken.hairline.value
    static let thin = BorderWidthToken.thin.value
    static let thick = BorderWidthToken.thick.value
}
