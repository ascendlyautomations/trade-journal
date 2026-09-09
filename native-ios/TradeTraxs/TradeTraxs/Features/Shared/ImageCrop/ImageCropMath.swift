import CoreGraphics
import Foundation

/// Fixed crop viewport layout — single source of truth for editor preview + export.
nonisolated struct ImageCropViewportLayout: Equatable {
    /// Minimum aspect-fill scale (viewport points per source pixel).
    let baseFillScale: CGFloat
    /// User zoom multiplier on top of base fill (1 = minimum cover).
    let userScale: CGFloat
    /// Pan offset from centered aspect-fill position (viewport points).
    let translation: CGSize
    /// Drawn image size in viewport coordinates.
    let displayWidth: CGFloat
    let displayHeight: CGFloat
    /// Top-left of drawn image in viewport coordinates.
    let origin: CGPoint

    var totalScale: CGFloat { baseFillScale * userScale }
}

/// Authoritative aspect-fill crop math — preview and export both use this.
nonisolated enum ImageCropViewportMath {
    static let minUserScale: CGFloat = 1
    static let maxUserScale: CGFloat = ImageCropMath.maxZoom

    static func baseFillScale(imagePixelSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return 1 }
        return max(
            viewportSize.width / imagePixelSize.width,
            viewportSize.height / imagePixelSize.height
        )
    }

    static func layout(
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        userScale: CGFloat,
        translation: CGSize,
        maxUserScale: CGFloat = maxUserScale
    ) -> ImageCropViewportLayout {
        let base = baseFillScale(imagePixelSize: imagePixelSize, viewportSize: viewportSize)
        let clampedUser = min(max(userScale, minUserScale), maxUserScale)
        let total = base * clampedUser
        let displayWidth = imagePixelSize.width * total
        let displayHeight = imagePixelSize.height * total

        let clampedOrigin = clampedOrigin(
            imagePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            translation: translation
        )

        let centeredX = (viewportSize.width - displayWidth) / 2
        let centeredY = (viewportSize.height - displayHeight) / 2
        let clampedTranslation = CGSize(
            width: clampedOrigin.x - centeredX,
            height: clampedOrigin.y - centeredY
        )

        return ImageCropViewportLayout(
            baseFillScale: base,
            userScale: clampedUser,
            translation: clampedTranslation,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            origin: clampedOrigin
        )
    }

    static func clampedTransform(
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        userScale: CGFloat,
        translation: CGSize,
        maxUserScale: CGFloat = maxUserScale
    ) -> ImageCropTransform {
        let resolved = layout(
            imagePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            userScale: userScale,
            translation: translation,
            maxUserScale: maxUserScale
        )
        return ImageCropTransform(zoom: resolved.userScale, offset: resolved.translation)
    }

    /// Pinch zoom anchored to a point in viewport coordinates.
    static func zoomAroundAnchor(
        anchor: CGPoint,
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        startUserScale: CGFloat,
        startTranslation: CGSize,
        magnification: CGFloat,
        maxUserScale: CGFloat = maxUserScale
    ) -> ImageCropTransform {
        let startLayout = layout(
            imagePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            userScale: startUserScale,
            translation: startTranslation,
            maxUserScale: maxUserScale
        )

        guard startLayout.displayWidth > 0, startLayout.displayHeight > 0 else {
            return ImageCropTransform(zoom: startUserScale, offset: startTranslation)
        }

        let imageFractionX = (anchor.x - startLayout.origin.x) / startLayout.displayWidth
        let imageFractionY = (anchor.y - startLayout.origin.y) / startLayout.displayHeight

        let newUserScale = min(max(startUserScale * magnification, minUserScale), maxUserScale)
        let base = startLayout.baseFillScale
        let newDisplayWidth = imagePixelSize.width * base * newUserScale
        let newDisplayHeight = imagePixelSize.height * base * newUserScale

        let originX = anchor.x - imageFractionX * newDisplayWidth
        let originY = anchor.y - imageFractionY * newDisplayHeight

        let clampedOrigin = clampedOriginPoint(
            viewportSize: viewportSize,
            displayWidth: newDisplayWidth,
            displayHeight: newDisplayHeight,
            proposedOrigin: CGPoint(x: originX, y: originY)
        )

        let centeredX = (viewportSize.width - newDisplayWidth) / 2
        let centeredY = (viewportSize.height - newDisplayHeight) / 2
        return ImageCropTransform(
            zoom: newUserScale,
            offset: CGSize(
                width: clampedOrigin.x - centeredX,
                height: clampedOrigin.y - centeredY
            )
        )
    }

    /// Source pixels currently visible through the fixed crop viewport.
    static func sourcePixelCrop(
        layout: ImageCropViewportLayout,
        viewportSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect {
        let iw = imagePixelSize.width
        let ih = imagePixelSize.height
        let vw = viewportSize.width
        let vh = viewportSize.height
        let scale = layout.totalScale

        guard scale > 0, layout.displayWidth > 0, layout.displayHeight > 0,
              iw > 0, ih > 0, vw > 0, vh > 0
        else {
            return CGRect(x: 0, y: 0, width: max(iw, 1), height: max(ih, 1))
        }

        let unclamped = CGRect(
            x: -layout.origin.x / scale,
            y: -layout.origin.y / scale,
            width: vw / scale,
            height: vh / scale
        )

        let left = max(0, unclamped.minX)
        let top = max(0, unclamped.minY)
        let right = min(iw, unclamped.maxX)
        let bottom = min(ih, unclamped.maxY)

        return CGRect(
            x: left,
            y: top,
            width: max(1, right - left),
            height: max(1, bottom - top)
        )
    }

    // MARK: - Private

    private static func clampedOrigin(
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        displayWidth: CGFloat,
        displayHeight: CGFloat,
        translation: CGSize
    ) -> CGPoint {
        let centeredX = (viewportSize.width - displayWidth) / 2 + translation.width
        let centeredY = (viewportSize.height - displayHeight) / 2 + translation.height
        return clampedOriginPoint(
            viewportSize: viewportSize,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            proposedOrigin: CGPoint(x: centeredX, y: centeredY)
        )
    }

    private static func clampedOriginPoint(
        viewportSize: CGSize,
        displayWidth: CGFloat,
        displayHeight: CGFloat,
        proposedOrigin: CGPoint
    ) -> CGPoint {
        var originX = proposedOrigin.x
        var originY = proposedOrigin.y
        let vw = viewportSize.width
        let vh = viewportSize.height

        if displayWidth > vw {
            originX = min(0, max(vw - displayWidth, originX))
        } else {
            originX = (vw - displayWidth) / 2
        }

        if displayHeight > vh {
            originY = min(0, max(vh - displayHeight, originY))
        } else {
            originY = (vh - displayHeight) / 2
        }

        return CGPoint(x: originX, y: originY)
    }
}

// MARK: - Legacy draw rect (Feed metadata / legacy render paths only)

nonisolated enum ImageCropMath {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 4

    struct DrawRect: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    static func clampZoom(_ zoom: CGFloat, maxZoom: CGFloat = maxZoom) -> CGFloat {
        min(maxZoom, max(minZoom, zoom))
    }

    // Legacy aspect-FIT math — Feed metadata / legacy render paths only (not crop editor).
    static func computeFitScale(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> CGFloat {
        guard imageWidth > 0, imageHeight > 0 else { return 1 }
        return min(frameWidth / imageWidth, frameHeight / imageHeight)
    }

    static func computeDrawRect(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) -> DrawRect {
        let fitScale = computeFitScale(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        let scale = fitScale * clampZoom(zoom)
        let width = imageWidth * scale
        let height = imageHeight * scale

        var x = (frameWidth - width) / 2 + offset.width
        var y = (frameHeight - height) / 2 + offset.height

        if width > frameWidth {
            x = min(0, max(frameWidth - width, x))
        } else {
            x = (frameWidth - width) / 2
        }

        if height > frameHeight {
            y = min(0, max(frameHeight - height, y))
        } else {
            y = (frameHeight - height) / 2
        }

        return DrawRect(x: x, y: y, width: width, height: height)
    }

    static func clampOffset(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGSize {
        let rect = computeDrawRect(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            zoom: zoom,
            offset: offset
        )
        let fitCenterX = (frameWidth - rect.width) / 2
        let fitCenterY = (frameHeight - rect.height) / 2

        if rect.width <= frameWidth, rect.height <= frameHeight {
            return .zero
        }

        return CGSize(
            width: rect.x - fitCenterX,
            height: rect.y - fitCenterY
        )
    }
}

#if DEBUG
enum CropTransformProbe {
    static func log(layout: ImageCropViewportLayout, viewport: CGSize, pinchAnchor: CGPoint?) {
        let anchorText: String
        if let pinchAnchor {
            anchorText = "(\(Int(pinchAnchor.x)),\(Int(pinchAnchor.y)))"
        } else {
            anchorText = "nil"
        }
        print(
            "[CropTransform] viewport=\(Int(viewport.width))x\(Int(viewport.height)) "
                + "baseScale=\(String(format: "%.4f", layout.baseFillScale)) "
                + "userScale=\(String(format: "%.3f", layout.userScale)) "
                + "translation=(\(Int(layout.translation.width)),\(Int(layout.translation.height))) "
                + "pinchAnchor=\(anchorText)"
        )
    }
}
#else
enum CropTransformProbe {
    static func log(layout: ImageCropViewportLayout, viewport: CGSize, pinchAnchor: CGPoint?) {}
}
#endif
