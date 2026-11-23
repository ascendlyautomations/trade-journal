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

/// Text plate behind story captions — cycles none → black → white in the editor.
enum StoryTextBackgroundStyle: String, Equatable, Sendable {
    case none
    case black
    case white

    mutating func cycle() {
        switch self {
        case .none: self = .black
        case .black: self = .white
        case .white: self = .none
        }
    }

    var swiftUIFill: Color {
        switch self {
        case .none: return .clear
        case .black: return Color.black.opacity(0.45)
        case .white: return Color.white.opacity(0.88)
        }
    }

    var uiKitFill: UIColor {
        switch self {
        case .none: return .clear
        case .black: return UIColor.black.withAlphaComponent(0.45)
        case .white: return UIColor.white.withAlphaComponent(0.88)
        }
    }
}

/// Canonical RGBA for a Story text element — presets and custom picker colors.
struct StoryTextFill: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    static func fromPreset(_ preset: StoryTextColor) -> StoryTextFill {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        preset.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return StoryTextFill(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }

    static func fromSwiftUIColor(_ color: Color) -> StoryTextFill {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return StoryTextFill(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    func matchesPreset(_ preset: StoryTextColor, tolerance: Double = 0.02) -> Bool {
        let reference = Self.fromPreset(preset)
        return abs(red - reference.red) <= tolerance
            && abs(green - reference.green) <= tolerance
            && abs(blue - reference.blue) <= tolerance
            && abs(alpha - reference.alpha) <= tolerance
    }

    var isCustomColor: Bool {
        !StoryTextColor.allCases.contains { matchesPreset($0) }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension TextAlignment {
    var storyFrameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct StoryTextOverlay: Identifiable, Equatable {
    var id: UUID
    var text: String
    /// Normalized center in canvas coordinates (0…1).
    var normalizedCenter: CGPoint
    var scale: CGFloat
    var rotationRadians: CGFloat
    var textFill: StoryTextFill
    var alignment: TextAlignment
    var backgroundStyle: StoryTextBackgroundStyle

    var showsBackground: Bool { backgroundStyle != .none }

    init(
        id: UUID = UUID(),
        text: String = "",
        normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationRadians: CGFloat = 0,
        textFill: StoryTextFill = .fromPreset(.white),
        alignment: TextAlignment = .leading,
        backgroundStyle: StoryTextBackgroundStyle = .none,
        showsBackground: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.normalizedCenter = normalizedCenter
        self.scale = scale
        self.rotationRadians = rotationRadians
        self.textFill = textFill
        self.alignment = alignment
        if let legacy = showsBackground {
            self.backgroundStyle = legacy ? .black : .none
        } else {
            self.backgroundStyle = backgroundStyle
        }
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

extension StoryTextOverlayRecord {
    init(_ overlay: StoryTextOverlay) {
        self.init(
            id: overlay.id,
            text: overlay.text,
            x: Double(overlay.normalizedCenter.x),
            y: Double(overlay.normalizedCenter.y),
            scale: Double(overlay.scale),
            rotation: Double(overlay.rotationRadians),
            red: overlay.textFill.red,
            green: overlay.textFill.green,
            blue: overlay.textFill.blue,
            alpha: overlay.textFill.alpha,
            alignment: Self.wireAlignment(overlay.alignment),
            background: overlay.showsBackground,
            background_style: overlay.backgroundStyle.rawValue
        )
    }

    func storyTextOverlay() -> StoryTextOverlay {
        let style: StoryTextBackgroundStyle
        if let raw = background_style, let parsed = StoryTextBackgroundStyle(rawValue: raw) {
            style = parsed
        } else {
            style = background ? .black : .none
        }
        return StoryTextOverlay(
            id: id,
            text: text,
            normalizedCenter: CGPoint(x: x, y: y),
            scale: CGFloat(scale),
            rotationRadians: CGFloat(rotation),
            textFill: StoryTextFill(red: red, green: green, blue: blue, alpha: alpha),
            alignment: Self.textAlignment(alignment),
            backgroundStyle: style
        )
    }

    func positionedForPlayback(videoPixelSize: CGSize, viewerSize: CGSize) -> StoryTextOverlay {
        var overlay = storyTextOverlay()
        overlay.normalizedCenter = StoryTextOverlayPlacement.viewerNormalizedCenter(
            composerNormalized: overlay.normalizedCenter,
            videoPixelSize: videoPixelSize,
            viewerSize: viewerSize
        )
        return overlay
    }

    private static func wireAlignment(_ alignment: TextAlignment) -> String {
        switch alignment {
        case .leading: return "leading"
        case .trailing: return "trailing"
        default: return "center"
        }
    }

    private static func textAlignment(_ alignment: String) -> TextAlignment {
        switch alignment {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }
}
