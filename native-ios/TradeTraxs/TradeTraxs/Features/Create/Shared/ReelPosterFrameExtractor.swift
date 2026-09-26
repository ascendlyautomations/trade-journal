import AVFoundation
import UIKit

/// Fast poster frame for instant Clip composer (no transcode, no AVPlayer).
enum ReelPosterFrameExtractor {
    struct PosterFrame: Sendable {
        var image: UIImage
        var jpegData: Data?
        var durationSeconds: Int
    }

    static func extractPoster(from videoURL: URL) async throws -> PosterFrame {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = max(1, Int(ceil(CMTimeGetSeconds(duration))))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let candidateSeconds: [Double] = [0, 0.1, 0.25, 0.5]
        var cgImage: CGImage?
        for seconds in candidateSeconds {
            try Task.checkCancellation()
            let time = CMTime(seconds: min(seconds, Double(durationSeconds)), preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image {
                cgImage = image
                break
            }
        }
        guard let cgImage else {
            throw AppError.unknown(message: "Could not read this video file.")
        }
        let image = UIImage(cgImage: cgImage)
        let jpeg = image.jpegData(compressionQuality: 0.82)
        return PosterFrame(image: image, jpegData: jpeg, durationSeconds: durationSeconds)
    }
}
