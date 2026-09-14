import AVFoundation
import UIKit

enum InlineClipFrameCapture {
    /// Captures an oriented frame near ``time`` — always off-main, low priority, never blocks scroll.
    static func captureFrame(asset: AVAsset, time: CMTime, maxPixelSize: CGFloat = 720) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

            guard let cgImage = try? await generator.image(at: time).image else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
