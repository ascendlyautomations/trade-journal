import SwiftUI

/// System Material tokens — prefer ``View/experienceMaterial(_:)`` in feature code.
/// Raw ``MaterialToken/material`` is light-mode / legacy; dark mode should never use it directly in views.
enum MaterialToken: Sendable {
    case ultraThin
    case thin
    case regular
    case thick
    case chrome

    /// System Material (light appearance). Do not apply directly in features — use ``experienceMaterial(_:)``.
    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .chrome: return .bar
        }
    }
}

enum ExperienceMaterials {
    static let sheet = MaterialToken.regular
    static let navBar = MaterialToken.chrome
    static let tabBar = MaterialToken.chrome
    static let overlay = MaterialToken.thin
    static let card = MaterialToken.ultraThin
}
