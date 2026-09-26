import UIKit

/// Shared chart-friendly image prep for trade screenshots, wall posts, and achievements.
enum MediaImagePreparation {
    /// Mild downscale + high JPEG quality so candle/text screenshots stay readable.
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 2560,
        quality: CGFloat = 0.92,
        logUpload: Bool = false
    ) -> Data? {
        let normalized = MediaImageOrientation.normalized(image)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let scale = min(1, maxDimension / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }
        let data = rendered.jpegData(compressionQuality: quality)
        #if DEBUG
        if logUpload {
            ImageUploadProbe.log(
                croppedImage: true,
                pixelSize: MediaImageOrientation.pixelSize(of: rendered),
                bytes: data?.count ?? 0
            )
        }
        #endif
        return data
    }

    /// Web `prepareStoryImageFile` — default compress preset (max width 1200).
    static func storyJPEGData(from image: UIImage) -> Data? {
        jpegData(from: image, maxDimension: 1200, quality: 0.92)
    }

    /// DM and room-chat attachments. Original aspect, longest edge at most 2560, no upscale.
    static let chatMaxLongestEdge: CGFloat = 2560
    static let chatJPEGQuality: CGFloat = 0.82

    static func chatOutputPixelSize(width: CGFloat, height: CGFloat) -> CGSize {
        let sourceWidth = max(0, floor(width))
        let sourceHeight = max(0, floor(height))
        let longest = max(sourceWidth, sourceHeight)
        guard longest > chatMaxLongestEdge, sourceWidth > 0, sourceHeight > 0 else {
            return CGSize(width: sourceWidth, height: sourceHeight)
        }
        if sourceWidth >= sourceHeight {
            let scaledHeight = max(1, floor(sourceHeight * chatMaxLongestEdge / sourceWidth))
            return CGSize(width: chatMaxLongestEdge, height: scaledHeight)
        }
        let scaledWidth = max(1, floor(sourceWidth * chatMaxLongestEdge / sourceHeight))
        return CGSize(width: scaledWidth, height: chatMaxLongestEdge)
    }

    /// One orientation bake, then one JPEG encode. Does not crop.
    static func chatJPEGData(from image: UIImage) -> Data? {
        let normalized = MediaImageOrientation.normalized(image)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let target = chatOutputPixelSize(width: pixelSize.width, height: pixelSize.height)
        let prepared: UIImage
        if abs(target.width - pixelSize.width) < 0.5, abs(target.height - pixelSize.height) < 0.5 {
            prepared = normalized
        } else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            prepared = renderer.image { _ in
                normalized.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        return prepared.jpegData(compressionQuality: chatJPEGQuality)
    }
}

#if DEBUG
enum ImageUploadProbe {
    static func log(croppedImage: Bool, pixelSize: CGSize, bytes: Int) {
        let aspect = pixelSize.width / max(pixelSize.height, 1)
        print(
            "[ImageUpload] croppedImage=\(croppedImage) "
                + "uploadPixels=\(Int(pixelSize.width))x\(Int(pixelSize.height)) "
                + "uploadAspectRatio=\(String(format: "%.4f", aspect)) "
                + "bytes=\(bytes)"
        )
    }
}
#else
enum ImageUploadProbe {
    static func log(croppedImage: Bool, pixelSize: CGSize, bytes: Int) {}
}
#endif
