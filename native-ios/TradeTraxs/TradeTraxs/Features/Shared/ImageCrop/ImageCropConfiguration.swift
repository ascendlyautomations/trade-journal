import CoreGraphics
import UIKit

/// Web-parity aspect presets for the shared crop editor.
nonisolated enum ImageCropAspectOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    case original
    case square
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .landscape: return "16:9"
        }
    }

    /// New trade, post, and achievement uploads. Original stays on the enum for existing content.
    static let feedAspectOptions: [ImageCropAspectOption] = [
        .square, .portrait, .landscape
    ]

    /// Compact segmented-control label (always short — no truncation on iPhone).
    var segmentTitle: String { title }

    /// `nil` uses the source image's natural aspect ratio (subject to Feed 4:5 cap).
    func aspectRatio(for imageSize: CGSize) -> CGFloat {
        switch self {
        case .original:
            guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
            return imageSize.width / imageSize.height
        case .square: return 1
        case .portrait: return 4 / 5
        case .landscape: return 16 / 9
        }
    }
}

nonisolated enum ImageCropMask: Sendable {
    case none
    /// Dim everything outside the Feed/Profile viewport rectangle.
    case feedViewport
    case circle
}

nonisolated enum ImageCropEditorPreset: Sendable {
    /// Feed posts, achievements, and general social uploads.
    case socialContent
    /// Trade screenshots.
    case tradeScreenshot
    /// Profile onboarding avatar.
    case avatar
    /// Trade room image.
    case room

    var title: String {
        switch self {
        case .socialContent: return "Adjust image"
        case .tradeScreenshot: return "Adjust screenshot"
        case .avatar: return "Profile picture"
        case .room: return "Room picture"
        }
    }

    var subtitle: String {
        switch self {
        case .socialContent:
            return "Drag and zoom to choose what appears in your post."
        case .tradeScreenshot:
            return "Drag and zoom to frame your chart."
        case .avatar:
            return "Drag and zoom to position your photo."
        case .room:
            return "Drag and zoom to position your room image."
        }
    }

    var allowedAspectOptions: [ImageCropAspectOption] {
        switch self {
        case .socialContent, .tradeScreenshot:
            return ImageCropAspectOption.feedAspectOptions
        case .avatar, .room:
            return [.square]
        }
    }

    var defaultAspectOption: ImageCropAspectOption {
        switch self {
        case .socialContent, .tradeScreenshot: return .portrait
        case .avatar, .room: return .square
        }
    }

    var mask: ImageCropMask {
        switch self {
        case .avatar, .room: return .circle
        case .socialContent, .tradeScreenshot: return .feedViewport
        }
    }

    var outputWidth: CGFloat {
        switch self {
        case .socialContent, .tradeScreenshot: return 1_200
        case .avatar, .room: return 512
        }
    }

    var maxZoom: CGFloat { ImageCropMath.maxZoom }
}

nonisolated struct ImageCropTransform: Equatable, Sendable {
    var zoom: CGFloat
    var offset: CGSize

    static let `default` = ImageCropTransform(zoom: 1, offset: .zero)
}

nonisolated struct ImageCropFrameSize: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat

    init(outputWidth: CGFloat, aspectRatio: CGFloat) {
        width = outputWidth
        height = max(1, round(outputWidth / max(aspectRatio, 0.01)))
    }
}
