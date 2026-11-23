import CoreGraphics
import SwiftUI
import UIKit

/// Composites the edited story canvas into a single upload-ready 9:16 image.
enum StoryImageRenderer {
    static func render(
        sourceImage: UIImage,
        canvas: StoryCanvasState,
        canvasSize: CGSize
    ) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let outputSize = StoryCanvasState.renderPixelSize
        let pixelScale = outputSize.width / canvasSize.width

        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))

            let imageRect = StoryImageLayout.drawRect(
                imageSize: sourceImage.size,
                canvasSize: canvasSize,
                scale: canvas.imageScale,
                offset: canvas.imageOffset
            )
            let scaledRect = CGRect(
                x: imageRect.origin.x * pixelScale,
                y: imageRect.origin.y * pixelScale,
                width: imageRect.width * pixelScale,
                height: imageRect.height * pixelScale
            )
            sourceImage.draw(in: scaledRect)

            for overlay in canvas.textOverlays where !overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StoryTextOverlayLayout.draw(
                    overlay: overlay,
                    in: context.cgContext,
                    canvasSize: canvasSize,
                    pixelScale: pixelScale
                )
            }
        }
    }
}

enum StoryImageLayout {
    /// Aspect-fit base rect inside the canvas, including user scale/offset (no edge snapping).
    static func drawRect(
        imageSize: CGSize,
        canvasSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let canvasAspect = canvasSize.width / canvasSize.height

        var drawSize: CGSize
        if imageAspect > canvasAspect {
            drawSize = CGSize(width: canvasSize.width, height: canvasSize.width / imageAspect)
        } else {
            drawSize = CGSize(width: canvasSize.height * imageAspect, height: canvasSize.height)
        }
        drawSize.width *= scale
        drawSize.height *= scale

        let origin = CGPoint(
            x: (canvasSize.width - drawSize.width) / 2 + offset.width,
            y: (canvasSize.height - drawSize.height) / 2 + offset.height
        )
        return CGRect(origin: origin, size: drawSize)
    }
}