import CoreGraphics
import Foundation

/// Persisted video-story text. Coordinates are normalized to the 9:16 composer canvas.
/// Photo stories burn text into the image and leave this empty.
nonisolated struct StoryTextOverlayRecord: Codable, Hashable, Sendable, Equatable {
    var id: UUID
    var text: String
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var alignment: String
    var background: Bool
}

/// Maps composer-canvas points onto a viewer that aspect-fills the same video.
nonisolated enum StoryTextOverlayPlacement {
    static func viewerNormalizedCenter(
        composerNormalized: CGPoint,
        videoPixelSize: CGSize,
        viewerSize: CGSize
    ) -> CGPoint {
        guard videoPixelSize.width > 1, videoPixelSize.height > 1,
              viewerSize.width > 1, viewerSize.height > 1
        else {
            return composerNormalized
        }

        let videoUV = videoNormalizedPoint(
            containerNormalized: composerNormalized,
            videoPixelSize: videoPixelSize,
            containerSize: composerCanvasSize
        )
        return containerNormalizedPoint(
            videoNormalized: videoUV,
            videoPixelSize: videoPixelSize,
            containerSize: viewerSize
        )
    }

    static func aspectFillRect(content: CGSize, container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = max(container.width / content.width, container.height / content.height)
        let width = content.width * scale
        let height = content.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private static var composerCanvasSize: CGSize { CGSize(width: 9, height: 16) }

    private static func videoNormalizedPoint(
        containerNormalized: CGPoint,
        videoPixelSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let fitted = aspectFillRect(content: videoPixelSize, container: containerSize)
        let containerPoint = CGPoint(
            x: containerNormalized.x * containerSize.width,
            y: containerNormalized.y * containerSize.height
        )
        return CGPoint(
            x: (containerPoint.x - fitted.minX) / fitted.width,
            y: (containerPoint.y - fitted.minY) / fitted.height
        )
    }

    private static func containerNormalizedPoint(
        videoNormalized: CGPoint,
        videoPixelSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let fitted = aspectFillRect(content: videoPixelSize, container: containerSize)
        let x = fitted.minX + videoNormalized.x * fitted.width
        let y = fitted.minY + videoNormalized.y * fitted.height
        return CGPoint(x: x / containerSize.width, y: y / containerSize.height)
    }
}
