import UIKit

/// Shared chart-friendly image prep for trade screenshots, wall posts, and achievements.
enum MediaImagePreparation {
    /// Mild downscale + high JPEG quality so candle/text screenshots stay readable.
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 2560,
        quality: CGFloat = 0.92
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
        return rendered.jpegData(compressionQuality: quality)
    }

    /// Web `prepareStoryImageFile` — default compress preset (max width 1200).
    static func storyJPEGData(from image: UIImage) -> Data? {
        jpegData(from: image, maxDimension: 1200, quality: 0.92)
    }
}
