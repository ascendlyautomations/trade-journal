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
                draw(
                    overlay: overlay,
                    in: context.cgContext,
                    canvasSize: canvasSize,
                    pixelScale: pixelScale
                )
            }
        }
    }

    private static func draw(
        overlay: StoryTextOverlay,
        in context: CGContext,
        canvasSize: CGSize,
        pixelScale: CGFloat
    ) {
        let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let baseFontSize = max(22, canvasSize.width * 0.065)
        let font = UIFont.systemFont(ofSize: baseFontSize * overlay.scale, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        switch overlay.alignment {
        case .leading: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: overlay.color.uiColor,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let maxWidth = canvasSize.width * 0.82
        let textBounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral

        let center = CGPoint(
            x: overlay.normalizedCenter.x * canvasSize.width,
            y: overlay.normalizedCenter.y * canvasSize.height
        )

        context.saveGState()
        context.translateBy(x: center.x * pixelScale, y: center.y * pixelScale)
        context.rotate(by: overlay.rotationRadians)
        context.scaleBy(x: pixelScale, y: pixelScale)

        var drawOrigin = CGPoint(
            x: -textBounds.width / 2,
            y: -textBounds.height / 2
        )
        switch overlay.alignment {
        case .leading: drawOrigin.x = -maxWidth / 2
        case .trailing: drawOrigin.x = maxWidth / 2 - textBounds.width
        default: break
        }

        if overlay.showsBackground {
            let pad: CGFloat = 8
            let bgRect = CGRect(
                x: drawOrigin.x - pad,
                y: drawOrigin.y - pad,
                width: max(textBounds.width, maxWidth) + pad * 2,
                height: textBounds.height + pad * 2
            )
            UIColor.black.withAlphaComponent(0.45).setFill()
            UIBezierPath(roundedRect: bgRect, cornerRadius: 8).fill()
        }

        attributed.draw(with: CGRect(origin: drawOrigin, size: textBounds.size), options: [.usesLineFragmentOrigin], context: nil)
        context.restoreGState()
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
