import UIKit

/// Shared chart-friendly image prep for trade screenshots, wall posts, and achievements.
enum MediaImagePreparation {
    static let avatarMaxDimension: CGFloat = 512
    static let avatarJPEGQuality: CGFloat = 0.85

    static let storyMaxWidth: CGFloat = 1080
    static let storyMaxHeight: CGFloat = 1920
    static let storyJPEGQuality: CGFloat = 0.85

    /// Trade, post, achievement, single Phase 1 delivery asset (~1440px long edge).
    static let contentMaxLongEdge: CGFloat = 1440
    static let contentJPEGQuality: CGFloat = 0.85

    static let contentPNGContentType = "image/png"
    static let contentJPEGContentType = "image/jpeg"

    struct ContentUploadPayload: Sendable {
        let data: Data
        let contentType: String

        var fileExtension: String {
            Self.fileExtension(for: contentType)
        }

        static func fileExtension(for contentType: String) -> String {
            contentType == contentPNGContentType ? "png" : "jpg"
        }
    }

    /// Encode content uploads: PNG when alpha is required, otherwise JPEG.
    static func contentUploadData(from image: UIImage, logUpload: Bool = false) -> ContentUploadPayload? {
        let normalized = MediaImageOrientation.normalized(image)
        if imageHasAlpha(normalized) {
            guard let data = pngData(from: normalized, maxDimension: contentMaxLongEdge), !data.isEmpty else {
                return nil
            }
            #if DEBUG
            if logUpload {
                ImageUploadProbe.log(
                    croppedImage: true,
                    pixelSize: MediaImageOrientation.pixelSize(of: normalized),
                    bytes: data.count
                )
            }
            #endif
            return ContentUploadPayload(data: data, contentType: contentPNGContentType)
        }
        guard let data = jpegData(from: normalized, logUpload: logUpload), !data.isEmpty else { return nil }
        return ContentUploadPayload(data: data, contentType: contentJPEGContentType)
    }

    static func contentType(forUploadData data: Data) -> String {
        guard data.count >= 4 else { return contentJPEGContentType }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return contentPNGContentType }
        return contentJPEGContentType
    }

    static func fileExtension(forUploadData data: Data) -> String {
        ContentUploadPayload.fileExtension(for: contentType(forUploadData: data))
    }

    static func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .noneSkipFirst, .noneSkipLast:
            return true
        default:
            return false
        }
    }

    /// Lossless PNG, mild downscale when needed; preserves alpha.
    static func pngData(from image: UIImage, maxDimension: CGFloat = contentMaxLongEdge) -> Data? {
        let rendered = downscaledPixelImage(from: image, maxDimension: maxDimension, preserveAlpha: true)
        return rendered.pngData()
    }

    /// Mild downscale + JPEG quality so candle/text screenshots stay readable.
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = contentMaxLongEdge,
        quality: CGFloat = contentJPEGQuality,
        logUpload: Bool = false
    ) -> Data? {
        let rendered = downscaledPixelImage(
            from: image,
            maxDimension: maxDimension,
            preserveAlpha: imageHasAlpha(image)
        )
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

    static func avatarJPEGData(from image: UIImage) -> Data? {
        jpegData(from: image, maxDimension: avatarMaxDimension, quality: avatarJPEGQuality)
    }

    /// Web `prepareImageForUpload("story")`, fit inside 1080×1920, preserve aspect.
    static func storyJPEGData(from image: UIImage) -> Data? {
        let normalized = MediaImageOrientation.normalized(image)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let scale = min(
            1,
            min(storyMaxWidth / max(pixelSize.width, 1), storyMaxHeight / max(pixelSize.height, 1))
        )
        let target = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: storyJPEGQuality)
    }

    /// DM and room-chat attachments. Original aspect, longest edge at most 1280, no upscale.
    static let chatMaxLongestEdge: CGFloat = 1280
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

    /// Reel poster thumbnails (~560×996 cover target).
    static let reelPosterMaxWidth: CGFloat = 560
    static let reelPosterMaxHeight: CGFloat = 996
    static let reelPosterJPEGQuality: CGFloat = 0.82

    static func reelPosterJPEGData(from image: UIImage) -> Data? {
        let normalized = MediaImageOrientation.normalized(image)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let target = CGSize(width: reelPosterMaxWidth, height: reelPosterMaxHeight)
        let scale = max(
            target.width / max(pixelSize.width, 1),
            target.height / max(pixelSize.height, 1)
        )
        let drawW = pixelSize.width * scale
        let drawH = pixelSize.height * scale
        let originX = (target.width - drawW) / 2
        let originY = (target.height - drawH) / 2
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            normalized.draw(in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
        }
        return rendered.jpegData(compressionQuality: reelPosterJPEGQuality)
    }

    private static func downscaledPixelImage(
        from image: UIImage,
        maxDimension: CGFloat,
        preserveAlpha: Bool
    ) -> UIImage {
        let normalized = MediaImageOrientation.normalized(image)
        let pixelSize = MediaImageOrientation.pixelSize(of: normalized)
        let scale = min(1, maxDimension / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !preserveAlpha
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { context in
            if preserveAlpha {
                context.cgContext.clear(CGRect(origin: .zero, size: target))
            }
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }
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
