import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Web `lib/reelVideo.ts` limits — validate + thumbnail locally; no server transcoding.
enum MediaVideoPreparation {
    static let maxDurationSeconds = 90
    static let maxFileBytes = 100 * 1024 * 1024
    static let maxCaptionLength = 2200
    static let durationLimitMessage = "Clips must be 90 seconds (1 minute 30 seconds) or less."

    private static let acceptedExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let acceptedTypes: Set<UTType> = [.mpeg4Movie, .quickTimeMovie, .movie]

    struct PreparedLocalVideo: Sendable {
        var fileURL: URL
        var contentType: String
        var byteCount: Int
        var durationSeconds: Int
        var thumbnailJPEG: Data?
        var thumbnailImage: UIImage?
    }

    static func isAcceptedVideo(url: URL, contentType: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        if acceptedExtensions.contains(ext) { return true }
        guard let contentType, let type = UTType(contentType) else { return false }
        return acceptedTypes.contains(where: { type.conforms(to: $0) })
    }

    static func validateFile(url: URL, contentType: String?) throws {
        guard isAcceptedVideo(url: url, contentType: contentType) else {
            throw AppError.unknown(message: "Clips support MP4 and MOV videos only.")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard size > 0, size <= maxFileBytes else {
            throw AppError.unknown(message: "Videos must be 100 MB or smaller.")
        }
    }

    /// Copy picker/camera file into a stable temp location, probe duration, capture poster frame.
    static func prepareLocalVideo(from sourceURL: URL, contentType: String?) async throws -> PreparedLocalVideo {
        try validateFile(url: sourceURL, contentType: contentType)

        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let asset = AVURLAsset(url: destination)
        let duration = try await asset.load(.duration)
        let seconds = Int(ceil(CMTimeGetSeconds(duration)))
        guard seconds > 0 else {
            throw AppError.unknown(message: "Could not process this video.")
        }
        guard seconds <= maxDurationSeconds else {
            throw AppError.unknown(message: durationLimitMessage)
        }

        let byteCount = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mime = mimeType(forExtension: ext, fallback: contentType)
        let thumb = await generateThumbnail(for: asset, durationSeconds: seconds)

        return PreparedLocalVideo(
            fileURL: destination,
            contentType: mime,
            byteCount: byteCount,
            durationSeconds: seconds,
            thumbnailJPEG: thumb?.jpegData(compressionQuality: 0.9),
            thumbnailImage: thumb
        )
    }

    static func formatDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func mimeType(forExtension ext: String, fallback: String?) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default:
            if let fallback, !fallback.isEmpty { return fallback }
            return "video/mp4"
        }
    }

    private static func generateThumbnail(for asset: AVURLAsset, durationSeconds: Int) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        // Prefer an early frame; fall back slightly later if needed (web seek candidates).
        let candidates: [Double] = [0.1, 0.5, 1.0, max(0.1, Double(durationSeconds) * 0.15)]
        for seconds in candidates {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }
}
