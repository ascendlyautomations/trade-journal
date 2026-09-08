import UIKit

/// Renders a zoom/pan crop to JPEG data — mirrors web `renderZoomPanCrop`.
enum ImageCropRenderer {
    static func render(
        sourceImage: UIImage,
        preset: ImageCropEditorPreset,
        aspectOption: ImageCropAspectOption,
        transform: ImageCropTransform
    ) -> UIImage? {
        let normalized = MediaImageOrientation.normalized(sourceImage)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let imageWidth = pixelSize.width
        let imageHeight = pixelSize.height
        guard imageWidth > 0, imageHeight > 0 else { return nil }

        let aspectRatio = aspectOption.aspectRatio(for: pixelSize)
        let frame = ImageCropFrameSize(outputWidth: preset.outputWidth, aspectRatio: aspectRatio)

        let zoom = ImageCropMath.clampZoom(transform.zoom, maxZoom: preset.maxZoom)
        let offset = ImageCropMath.clampOffset(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            frameWidth: frame.width,
            frameHeight: frame.height,
            zoom: zoom,
            offset: transform.offset
        )
        let rect = ImageCropMath.computeDrawRect(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            frameWidth: frame.width,
            frameHeight: frame.height,
            zoom: zoom,
            offset: offset
        )

        let outputWidth = Int(frame.width)
        let outputHeight = Int(frame.height)
        let scaleX = preset.outputWidth / frame.width
        let scaleY = CGFloat(outputHeight) / frame.height

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputWidth, height: outputHeight),
            format: format
        )
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

            if preset.mask == .circle {
                let radius = min(CGFloat(outputWidth), CGFloat(outputHeight)) / 2
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(
                    x: CGFloat(outputWidth) / 2 - radius,
                    y: CGFloat(outputHeight) / 2 - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                ctx.clip()
            }

            normalized.draw(
                in: CGRect(
                    x: rect.x * scaleX,
                    y: rect.y * scaleY,
                    width: rect.width * scaleX,
                    height: rect.height * scaleY
                )
            )

            if preset.mask == .circle {
                ctx.restoreGState()
            }
        }
    }

    static func jpegData(
        sourceImage: UIImage,
        preset: ImageCropEditorPreset,
        aspectOption: ImageCropAspectOption,
        transform: ImageCropTransform,
        maxDimension: CGFloat = 2_560,
        quality: CGFloat = 0.92
    ) -> Data? {
        guard let rendered = render(
            sourceImage: sourceImage,
            preset: preset,
            aspectOption: aspectOption,
            transform: transform
        ) else { return nil }
        return MediaImagePreparation.jpegData(from: rendered, maxDimension: maxDimension, quality: quality)
    }
}
