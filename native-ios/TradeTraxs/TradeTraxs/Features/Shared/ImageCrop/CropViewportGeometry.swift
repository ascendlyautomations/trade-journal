import CoreGraphics
import Foundation

/// Canonical crop-viewport geometry — preview and export both derive from this model.
struct CropViewportGeometry: Equatable {
    let sourcePixelSize: CGSize
    let viewportSize: CGSize
    let layout: ImageCropViewportLayout

    init(
        sourcePixelSize: CGSize,
        viewportSize: CGSize,
        userScale: CGFloat,
        translation: CGSize,
        maxUserScale: CGFloat = ImageCropViewportMath.maxUserScale
    ) {
        self.sourcePixelSize = sourcePixelSize
        self.viewportSize = viewportSize
        self.layout = ImageCropViewportMath.layout(
            imagePixelSize: sourcePixelSize,
            viewportSize: viewportSize,
            userScale: userScale,
            translation: translation,
            maxUserScale: maxUserScale
        )
    }

    var effectiveScale: CGFloat { layout.totalScale }

    var renderedSize: CGSize {
        CGSize(width: layout.displayWidth, height: layout.displayHeight)
    }

    var renderedOrigin: CGPoint { layout.origin }

    /// UIKit frame for the preview `UIImageView` inside the crop viewport (top-left space).
    var previewImageFrame: CGRect {
        CGRect(
            x: layout.origin.x,
            y: layout.origin.y,
            width: layout.displayWidth,
            height: layout.displayHeight
        )
    }

    /// Source-pixel rect visible through the viewport before edge clamping.
    var sourceRectBeforeClamp: CGRect {
        let scale = effectiveScale
        guard scale > 0,
              viewportSize.width > 0,
              viewportSize.height > 0
        else {
            return CGRect(origin: .zero, size: sourcePixelSize)
        }
        return CGRect(
            x: -layout.origin.x / scale,
            y: -layout.origin.y / scale,
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
    }

    /// Source-pixel rect used for `CGImage.cropping(to:)` — clamped to bitmap bounds.
    func sourcePixelCropRect() -> CGRect {
        ImageCropViewportMath.sourcePixelCrop(
            layout: layout,
            viewportSize: viewportSize,
            imagePixelSize: sourcePixelSize
        )
    }

    var previewSourceTop: CGFloat { sourceRectBeforeClamp.minY }
    var previewSourceCenter: CGFloat { sourceRectBeforeClamp.midY }
    var previewSourceBottom: CGFloat { sourceRectBeforeClamp.maxY }
}

#if DEBUG
enum CropGeometryProbe {
    static func logPreview(_ geometry: CropViewportGeometry) {
        let source = geometry.sourcePixelSize
        let viewport = geometry.viewportSize
        let layout = geometry.layout
        let rendered = geometry.renderedSize
        let origin = geometry.renderedOrigin
        print(
            "[CropGeometry] sourcePixels=\(Int(source.width))x\(Int(source.height)) "
                + "viewportPoints=\(String(format: "%.2f", viewport.width))x\(String(format: "%.2f", viewport.height)) "
                + "baseScale=\(String(format: "%.6f", layout.baseFillScale)) "
                + "userScale=\(String(format: "%.6f", layout.userScale)) "
                + "effectiveScale=\(String(format: "%.6f", geometry.effectiveScale)) "
                + "translation=(\(String(format: "%.2f", layout.translation.width)),\(String(format: "%.2f", layout.translation.height))) "
                + "renderedSize=(\(String(format: "%.2f", rendered.width)),\(String(format: "%.2f", rendered.height))) "
                + "renderedOrigin=(\(String(format: "%.2f", origin.x)),\(String(format: "%.2f", origin.y)))"
        )
    }

    static func logExport(
        geometry: CropViewportGeometry,
        beforeClamp: CGRect,
        afterClamp: CGRect,
        pixelRect: CGRect,
        outputPixels: CGSize
    ) {
        print(
            "[CropExport] sourceRectBeforeClamp="
                + rect(beforeClamp)
                + " sourceRectAfterClamp="
                + rect(afterClamp)
                + " pixelRect="
                + rect(pixelRect)
                + " outputPixels=\(Int(outputPixels.width))x\(Int(outputPixels.height))"
        )
        print(
            "[CropParity] previewSourceTop=\(String(format: "%.3f", geometry.previewSourceTop)) "
                + "previewSourceCenter=\(String(format: "%.3f", geometry.previewSourceCenter)) "
                + "previewSourceBottom=\(String(format: "%.3f", geometry.previewSourceBottom)) "
                + "exportSourceTop=\(String(format: "%.3f", afterClamp.minY)) "
                + "exportSourceCenter=\(String(format: "%.3f", afterClamp.midY)) "
                + "exportSourceBottom=\(String(format: "%.3f", afterClamp.maxY))"
        )
    }

    private static func rect(_ rect: CGRect) -> String {
        String(
            format: "x=%.3f y=%.3f w=%.3f h=%.3f",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }
}
#else
enum CropGeometryProbe {
    static func logPreview(_ geometry: CropViewportGeometry) {}
    static func logExport(
        geometry: CropViewportGeometry,
        beforeClamp: CGRect,
        afterClamp: CGRect,
        pixelRect: CGRect,
        outputPixels: CGSize
    ) {}
}
#endif
