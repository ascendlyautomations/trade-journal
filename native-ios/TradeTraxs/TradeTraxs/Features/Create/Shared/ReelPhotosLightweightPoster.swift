import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Fast composer poster from PhotoKit — no full video transferable load.
enum ReelPhotosLightweightPoster {
    struct Result: Sendable {
        var image: UIImage
        var jpegData: Data?
        var durationSeconds: Int
    }

    static func fetch(from item: PhotosPickerItem) async -> Result? {
        guard let identifier = item.itemIdentifier else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .video else { return nil }

        let durationSeconds = max(1, Int(round(asset.duration)))
        let targetSize = CGSize(width: 1080, height: 1920)

        guard let image = await requestPosterImage(for: asset, targetSize: targetSize) else {
            return nil
        }
        return Result(
            image: image,
            jpegData: image.jpegData(compressionQuality: 0.82),
            durationSeconds: durationSeconds
        )
    }

    private static func requestPosterImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let resumeOnce = PosterResumeOnce(continuation)

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.version = .current

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if info?[PHImageCancelledKey] as? Bool == true {
                    resumeOnce.resume(returning: nil)
                    return
                }
                if info?[PHImageErrorKey] != nil {
                    resumeOnce.resume(returning: nil)
                    return
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard let image, !isDegraded else { return }
                resumeOnce.resume(returning: image)
            }
        }
    }
}

private final class PosterResumeOnce: @unchecked Sendable {
    private let continuation: CheckedContinuation<UIImage?, Never>
    private var didResume = false
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
