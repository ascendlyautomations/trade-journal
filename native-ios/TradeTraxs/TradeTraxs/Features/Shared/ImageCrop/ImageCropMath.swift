import CoreGraphics

/// Zoom/pan crop math — mirrors web `lib/zoomPanCrop.ts`.
enum ImageCropMath {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 4

    struct DrawRect: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    static func computeFitScale(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> CGFloat {
        guard imageWidth > 0, imageHeight > 0 else { return 1 }
        return min(frameWidth / imageWidth, frameHeight / imageHeight)
    }

    static func clampZoom(_ zoom: CGFloat, maxZoom: CGFloat = maxZoom) -> CGFloat {
        min(maxZoom, max(minZoom, zoom))
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
