import UIKit

/// Exports the exact visible crop from the editor into a new upright UIImage at source-pixel resolution.
enum ImageCropRenderer {
    /// Default cap — mild downscale only when the crop exceeds this on its longest edge.
    static let defaultMaxOutputDimension: CGFloat = 2_560

    /// Exports feed/trade/achievement crops — pixels in the returned image are authoritative for upload.
    static func exportFeedCrop(
        sourceImage: UIImage,
        aspectOption: ImageCropAspectOption,
        viewportSize: CGSize,
        transform: ImageCropTransform,
        maxUserScale: CGFloat = ImageCropMath.maxZoom,
        maxOutputDimension: CGFloat = defaultMaxOutputDimension
    ) -> UIImage? {
        let normalized = MediaImageOrientation.normalized(sourceImage)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let imageAspect = pixelSize.width / max(pixelSize.height, 1)
        let requiresFill = FeedMediaLayout.requiresFillCrop(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )

        if !requiresFill {
            #if DEBUG
            CropExportProbe.log(
                mode: aspectOption,
                sourcePixels: pixelSize,
                viewport: viewportSize,
                layout: nil,
                sourceCropRect: nil,
                output: normalized
            )
            #endif
            return normalized
        }

        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let geometry = CropViewportGeometry(
            sourcePixelSize: pixelSize,
            viewportSize: viewportSize,
            userScale: transform.zoom,
            translation: transform.offset,
            maxUserScale: maxUserScale
        )

        return exportFeedCrop(
            sourceImage: normalized,
            aspectOption: aspectOption,
            geometry: geometry,
            maxOutputDimension: maxOutputDimension
        )
    }

    /// Exports using canonical geometry — preview and export must share this object.
    static func exportFeedCrop(
        sourceImage: UIImage,
        aspectOption: ImageCropAspectOption,
        geometry: CropViewportGeometry,
        maxOutputDimension: CGFloat = defaultMaxOutputDimension
    ) -> UIImage? {
        let normalized = MediaImageOrientation.normalized(sourceImage)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let imageAspect = pixelSize.width / max(pixelSize.height, 1)
        let requiresFill = FeedMediaLayout.requiresFillCrop(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )

        if !requiresFill {
            #if DEBUG
            CropExportProbe.log(
                mode: aspectOption,
                sourcePixels: pixelSize,
                viewport: geometry.viewportSize,
                layout: nil,
                sourceCropRect: nil,
                output: normalized
            )
            #endif
            return normalized
        }

        let beforeClamp = geometry.sourceRectBeforeClamp
        let afterClamp = geometry.sourcePixelCropRect()

        guard let output = cropSourcePixels(
            normalized,
            cropRect: afterClamp,
            maxOutputDimension: maxOutputDimension
        ) else { return nil }

        #if DEBUG
        let pixelRect = afterClamp.pixelIntegralClamped(to: pixelSize)
        CropGeometryProbe.logPreview(geometry)
        CropGeometryProbe.logExport(
            geometry: geometry,
            beforeClamp: beforeClamp,
            afterClamp: afterClamp,
            pixelRect: pixelRect,
            outputPixels: MediaImageOrientation.pixelSize(of: output)
        )
        CropExportProbe.log(
            mode: aspectOption,
            sourcePixels: pixelSize,
            viewport: geometry.viewportSize,
            layout: geometry.layout,
            sourceCropRect: afterClamp,
            output: output
        )
        CropExportProbe.assertExpectedAspect(mode: aspectOption, output: output)
        #endif
        return output
    }

    /// Avatar / room — fixed output size with optional circle mask (unchanged contract).
    static func render(
        sourceImage: UIImage,
        preset: ImageCropEditorPreset,
        aspectOption: ImageCropAspectOption,
        transform: ImageCropTransform
    ) -> UIImage? {
        let normalized = MediaImageOrientation.normalized(sourceImage)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let aspectRatio = aspectOption.aspectRatio(for: pixelSize)
        let frame = ImageCropFrameSize(outputWidth: preset.outputWidth, aspectRatio: aspectRatio)
        let viewport = CGSize(width: frame.width, height: frame.height)

        let layout = ImageCropViewportMath.layout(
            imagePixelSize: pixelSize,
            viewportSize: viewport,
            userScale: transform.zoom,
            translation: transform.offset,
            maxUserScale: preset.maxZoom
        )

        let sourceCropRect = ImageCropViewportMath.sourcePixelCrop(
            layout: layout,
            viewportSize: viewport,
            imagePixelSize: pixelSize
        )

        guard let cropped = cropSourcePixels(
            normalized,
            cropRect: sourceCropRect,
            maxOutputDimension: max(frame.width, frame.height)
        ) else { return nil }

        let outputWidth = Int(frame.width)
        let outputHeight = Int(frame.height)
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

            cropped.draw(in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

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

    // MARK: - Pixel crop

    private static func cropSourcePixels(
        _ normalized: UIImage,
        cropRect: CGRect,
        maxOutputDimension: CGFloat
    ) -> UIImage? {
        guard let cgImage = normalized.cgImage else { return nil }
        let bounds = MediaImageOrientation.pixelSize(of: normalized)
        let pixelRect = cropRect.pixelIntegralClamped(to: bounds)
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let croppedCG = cgImage.cropping(to: pixelRect)
        else { return nil }

        let cropped = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
        return downscaleIfNeeded(cropped, maxDimension: maxOutputDimension)
    }

    private static func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelSize = MediaImageOrientation.pixelSize(of: image)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > maxDimension, maxDimension > 0 else { return image }

        let scale = maxDimension / longest
        let target = CGSize(
            width: floor(pixelSize.width * scale),
            height: floor(pixelSize.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension CGRect {
    /// Float-space clamp, then integralize once for `CGImage.cropping(to:)`.
    func pixelIntegralClamped(to bounds: CGSize) -> CGRect {
        let maxW = bounds.width
        let maxH = bounds.height
        guard maxW > 0, maxH > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let x = max(0, min(origin.x, maxW - 1))
        let y = max(0, min(origin.y, maxH - 1))
        let w = max(1, min(width, maxW - x))
        let h = max(1, min(height, maxH - y))

        let pixelX = floor(x)
        let pixelY = floor(y)
        let pixelMaxX = min(maxW, ceil(x + w))
        let pixelMaxY = min(maxH, ceil(y + h))

        return CGRect(
            x: pixelX,
            y: pixelY,
            width: max(1, pixelMaxX - pixelX),
            height: max(1, pixelMaxY - pixelY)
        )
    }
}

#if DEBUG
enum CropExportProbe {
    private static let aspectTolerance: CGFloat = 0.03

    static func log(
        mode: ImageCropAspectOption,
        sourcePixels: CGSize,
        viewport: CGSize,
        layout: ImageCropViewportLayout?,
        sourceCropRect: CGRect?,
        output: UIImage
    ) {
        let outputPixels = MediaImageOrientation.pixelSize(of: output)
        let actualAspect = outputPixels.width / max(outputPixels.height, 1)
        let expectedAspect = expectedAspectRatio(for: mode, sourcePixels: sourcePixels)

        let visibleText: String
        if let layout {
            let normalized = normalizedVisibleRect(
                layout: layout,
                viewport: viewport,
                sourcePixels: sourcePixels
            )
            visibleText = String(
                format: "x=%.4f y=%.4f w=%.4f h=%.4f",
                normalized.minX, normalized.minY, normalized.width, normalized.height
            )
        } else {
            visibleText = "full"
        }

        let pixelCropText: String
        if let sourceCropRect {
            pixelCropText = String(
                format: "x=%.0f y=%.0f w=%.0f h=%.0f",
                sourceCropRect.origin.x,
                sourceCropRect.origin.y,
                sourceCropRect.width,
                sourceCropRect.height
            )
        } else {
            pixelCropText = "full"
        }

        print(
            "[CropExport] mode=\(mode.rawValue) "
                + "source=\(Int(sourcePixels.width))x\(Int(sourcePixels.height)) "
                + "viewport=\(Int(viewport.width))x\(Int(viewport.height)) "
                + "visibleSourceRect=\(visibleText) "
                + "pixelCropRect=\(pixelCropText) "
                + "outputPixels=\(Int(outputPixels.width))x\(Int(outputPixels.height)) "
                + "expectedAspect=\(String(format: "%.4f", expectedAspect)) "
                + "actualAspect=\(String(format: "%.4f", actualAspect))"
        )

        if let layout {
            print(
                "[CropExport] baseScale=\(String(format: "%.4f", layout.baseFillScale)) "
                    + "userScale=\(String(format: "%.3f", layout.userScale)) "
                    + "translation=(\(Int(layout.translation.width)),\(Int(layout.translation.height)))"
            )
        }
    }

    static func assertExpectedAspect(mode: ImageCropAspectOption, output: UIImage) {
        let pixels = MediaImageOrientation.pixelSize(of: output)
        let actual = pixels.width / max(pixels.height, 1)
        let expected = expectedAspectRatio(for: mode, sourcePixels: pixels)
        guard abs(actual - expected) > aspectTolerance else { return }
        assertionFailure(
            "[CropExport] aspect mismatch mode=\(mode.rawValue) "
                + "expected=\(expected) actual=\(actual) "
                + "pixels=\(Int(pixels.width))x\(Int(pixels.height))"
        )
    }

    private static func normalizedVisibleRect(
        layout: ImageCropViewportLayout,
        viewport: CGSize,
        sourcePixels: CGSize
    ) -> CGRect {
        let pixelRect = ImageCropViewportMath.sourcePixelCrop(
            layout: layout,
            viewportSize: viewport,
            imagePixelSize: sourcePixels
        )
        guard sourcePixels.width > 0, sourcePixels.height > 0 else { return .zero }
        return CGRect(
            x: pixelRect.origin.x / sourcePixels.width,
            y: pixelRect.origin.y / sourcePixels.height,
            width: pixelRect.width / sourcePixels.width,
            height: pixelRect.height / sourcePixels.height
        )
    }

    private static func expectedAspectRatio(
        for mode: ImageCropAspectOption,
        sourcePixels: CGSize
    ) -> CGFloat {
        switch mode {
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        case .original:
            let imageAspect = sourcePixels.width / max(sourcePixels.height, 1)
            if FeedMediaLayout.exceedsFeedPortraitLimit(imageAspect: imageAspect) {
                return FeedMediaLayout.minimumFeedAspectRatio
            }
            return imageAspect
        }
    }
}

enum CropDoneProbe {
    static func log(sourcePixels: CGSize, mode: ImageCropAspectOption, result: UIImage) {
        let resultPixels = MediaImageOrientation.pixelSize(of: result)
        let aspect = resultPixels.width / max(resultPixels.height, 1)
        print(
            "[CropDone] sourcePixels=\(Int(sourcePixels.width))x\(Int(sourcePixels.height)) "
                + "mode=\(mode.rawValue) "
                + "resultPixels=\(Int(resultPixels.width))x\(Int(resultPixels.height)) "
                + "resultAspect=\(String(format: "%.4f", aspect))"
        )
    }
}
#else
enum CropExportProbe {
    static func log(
        mode: ImageCropAspectOption,
        sourcePixels: CGSize,
        viewport: CGSize,
        layout: ImageCropViewportLayout?,
        sourceCropRect: CGRect?,
        output: UIImage
    ) {}
    static func assertExpectedAspect(mode: ImageCropAspectOption, output: UIImage) {}
}
enum CropDoneProbe {
    static func log(sourcePixels: CGSize, mode: ImageCropAspectOption, result: UIImage) {}
}
#endif
