import SwiftUI

enum MaterialToken: Sendable {
    case ultraThin
    case thin
    case regular
    case thick
    case chrome

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

extension View {
    func experienceMaterial(_ token: MaterialToken) -> some View {
        background(token.material)
    }
}
