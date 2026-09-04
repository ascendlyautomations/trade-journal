import Foundation
import SwiftUI

enum StoryTextColor: String, CaseIterable, Identifiable, Equatable {
    case white
    case black
    case accentBlue
    case accentGreen
    case accentRed
    case accentYellow

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .accentBlue: return UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)
        case .accentGreen: return UIColor(red: 0.35, green: 0.88, blue: 0.55, alpha: 1)
        case .accentRed: return UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
        case .accentYellow: return UIColor(red: 1, green: 0.88, blue: 0.25, alpha: 1)
        }
    }

    var swiftUIColor: Color { Color(uiColor) }
}

struct StoryTextOverlay: Identifiable, Equatable {
    var id: UUID
    var text: String
    /// Normalized center in canvas coordinates (0…1).
    var normalizedCenter: CGPoint
    var scale: CGFloat
    var rotationRadians: CGFloat
    var color: StoryTextColor
    var alignment: TextAlignment
    var showsBackground: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationRadians: CGFloat = 0,
        color: StoryTextColor = .white,
        alignment: TextAlignment = .center,
        showsBackground: Bool = false
    ) {
        self.id = id
        self.text = text
        self.normalizedCenter = normalizedCenter
        self.scale = scale
        self.rotationRadians = rotationRadians
        self.color = color
        self.alignment = alignment
        self.showsBackground = showsBackground
    }
}

struct StoryCanvasState: Equatable {
    var imageScale: CGFloat = 1
    var imageOffset: CGSize = .zero
    var textOverlays: [StoryTextOverlay] = []
    var selectedTextID: UUID?

    static let canvasAspectRatio: CGFloat = 9 / 16
    static let renderPixelSize = CGSize(width: 1080, height: 1920)

    mutating func resetTransforms() {
        imageScale = 1
        imageOffset = .zero
        textOverlays = []
        selectedTextID = nil
    }
}
