import CryptoKit
import Foundation
import UIKit

/// Compresses screenshots before AI upload while keeping numbers readable.
nonisolated enum ScreenshotAIImagePreparer {
    static let maxImages = 8
    static let maxPixelWidth: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.72

    struct PreparedImage: Hashable, Sendable {
        var index: Int
        var mimeType: String
        var base64: String
    }

    static func prepare(_ images: [UIImage], limit: Int = maxImages) -> [PreparedImage] {
        images.prefix(limit).enumerated().compactMap { index, image in
            guard let data = jpegData(from: image) else { return nil }
            return PreparedImage(
                index: index,
                mimeType: "image/jpeg",
                base64: data.base64EncodedString()
            )
        }
    }

    private static func jpegData(from image: UIImage) -> Data? {
        let targetWidth = min(maxPixelWidth, image.size.width)
        let scale = targetWidth / max(image.size.width, 1)
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}

/// Redacts sensitive OCR text before sending layout hints to the BFF.
nonisolated enum ScreenshotSensitiveOCRRedactor {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#,
            #"\b(?:account|acct|acc)\s*#?\s*\d{4,}\b"#,
            #"\b(?:balance|equity|net liq(?:uidation)?)\s*[:$]?\s*[\d,]+(?:\.\d+)?\b"#,
            #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    static func redact(_ text: String) -> String {
        var output = text
        for regex in patterns {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: "[redacted]"
            )
        }
        return output
    }

    static func redactBlocks(_ blocks: [OCRTextBlock]) -> [ScreenshotAIExtractRequest.OCRBlockPayload] {
        blocks.map { block in
            ScreenshotAIExtractRequest.OCRBlockPayload(
                text: redact(block.text),
                x: Double(block.boundingBox.minX),
                y: Double(block.boundingBox.minY),
                width: Double(block.boundingBox.width),
                height: Double(block.boundingBox.height)
            )
        }
    }
}

/// Session-only fingerprint for AI request dedup/cache (no raw image persistence).
nonisolated enum ScreenshotAIRequestFingerprint {
    static func make(
        images: [ScreenshotAIImagePreparer.PreparedImage],
        ocrBlocks: [[OCRTextBlock]]
    ) -> String {
        var parts: [String] = ["v1"]
        for image in images {
            parts.append("img:\(image.index):\(image.base64.prefix(64))")
        }
        for (index, blocks) in ocrBlocks.enumerated() {
            let text = blocks.map { ScreenshotSensitiveOCRRedactor.redact($0.text) }.joined(separator: "|")
            parts.append("ocr:\(index):\(text.hashValue)")
        }
        let payload = parts.joined(separator: ";")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "v1:\(hex.prefix(32))"
    }
}
