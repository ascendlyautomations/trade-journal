import UIKit

/// Shared chart-friendly image prep for trade screenshots, wall posts, and achievements.
enum MediaImagePreparation {
    /// Mild downscale + high JPEG quality so candle/text screenshots stay readable.
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 2560,
        quality: CGFloat = 0.92
    ) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// Web `prepareStoryImageFile` — default compress preset (max width 1200).
    static func storyJPEGData(from image: UIImage) -> Data? {
        jpegData(from: image, maxDimension: 1200, quality: 0.92)
    }
}
