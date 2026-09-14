import UIKit

/// EXIF / UIImage orientation — normalize once before crop math, encode, and display sizing.
nonisolated enum MediaImageOrientation {
    /// Bakes orientation into pixels. Returns `.up` at scale 1.
    nonisolated static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1, image.cgImage != nil {
            return image
        }

        let pixelSize = orientedPixelSize(for: image)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    /// Visual pixel width/height after applying orientation metadata.
    nonisolated static func pixelSize(of image: UIImage) -> CGSize {
        resolvedPixelSize(normalized(image))
    }

    nonisolated static func aspectRatio(of image: UIImage) -> CGFloat {
        let size = pixelSize(of: image)
        return max(size.width, 1) / max(size.height, 1)
    }

    /// Visual pixel dimensions without re-baking orientation — for already-normalized display bitmaps.
    nonisolated static func visualPixelSize(of image: UIImage) -> CGSize {
        if image.imageOrientation == .up, image.scale == 1, let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return pixelSize(of: image)
    }

    nonisolated static func visualAspectRatio(of image: UIImage) -> CGFloat {
        let size = visualPixelSize(of: image)
        return max(size.width, 1) / max(size.height, 1)
    }

    // MARK: - Private

    nonisolated private static func resolvedPixelSize(_ image: UIImage) -> CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
    }

    nonisolated private static func orientedPixelSize(for image: UIImage) -> CGSize {
        if let cg = image.cgImage {
            switch image.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                return CGSize(width: cg.height, height: cg.width)
            default:
                return CGSize(width: cg.width, height: cg.height)
            }
        }
        return image.size
    }
}
