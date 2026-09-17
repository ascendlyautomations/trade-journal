import CoreTransferable
import ImageIO
import OSLog
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if DEBUG
nonisolated enum ProfilePhotoDebugLog {
    static func selectionChanged(hasItem: Bool) {
        AppLog.profilePhoto.debug("[ProfilePhoto] picker.selectionChanged hasItem=\(hasItem, privacy: .public)")
    }

    static func transferableLoadStarted() {
        AppLog.profilePhoto.debug("[ProfilePhoto] transferable.load.started")
    }

    static func transferableLoadCompleted() {
        AppLog.profilePhoto.debug("[ProfilePhoto] transferable.load.completed")
    }

    static func decodeStarted() {
        AppLog.profilePhoto.debug("[ProfilePhoto] decode.started")
    }

    static func decodeCompleted(width: Int, height: Int) {
        AppLog.profilePhoto.debug(
            "[ProfilePhoto] decode.completed width=\(width, privacy: .public) height=\(height, privacy: .public)"
        )
    }

    static func cropperPresented() {
        AppLog.profilePhoto.debug("[ProfilePhoto] cropper.presented")
    }

    static func loadFailed(stage: String, errorType: String) {
        AppLog.profilePhoto.debug(
            "[ProfilePhoto] load.failed stage=\(stage, privacy: .public) errorType=\(errorType, privacy: .public)"
        )
    }
}
#endif

/// Profile avatars — still images only (no Live Photo motion components in the picker).
enum ProfilePhotoPickerFilter {
    static let matching: PHPickerFilter = .any(of: [.images, .not(.livePhotos)])
}

/// PhotosPicker → UIImage for crop flows (HEIC/HEIF/JPEG/PNG, ImageIO fallback).
private struct PickedPhotoTransferable: Transferable {
    let uiImage: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
        DataRepresentation(importedContentType: .heic) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
        DataRepresentation(importedContentType: .heif) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
        DataRepresentation(importedContentType: .png) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
        DataRepresentation(importedContentType: .webP) { data in
            try PickedPhotoTransferable(uiImage: PhotosPickerImageDecoder.decode(data))
        }
    }
}

/// ImageIO / UIKit decode — safe off MainActor (Transferable import runs on a background executor).
private nonisolated enum PhotosPickerImageDecoder {
    enum Stage: String, Sendable {
        case transferableLoad = "transferableLoad"
        case dataFallback = "dataFallback"
        case decode = "decode"
        case normalize = "normalize"
    }

    static func decode(_ data: Data) throws -> UIImage {
        guard !data.isEmpty else {
            throw PhotosPickerImageDecodeError.emptyData
        }
        if looksLikeVideoContainer(data) {
            throw PhotosPickerImageDecodeError.unsupportedFormat
        }
#if DEBUG
        ProfilePhotoDebugLog.decodeStarted()
#endif
        if let image = decodeViaImageIO(data) ?? UIImage(data: data) {
            let pixels = MediaImageOrientation.pixelSize(of: image)
#if DEBUG
            ProfilePhotoDebugLog.decodeCompleted(
                width: Int(pixels.width.rounded()),
                height: Int(pixels.height.rounded())
            )
#endif
            return image
        }
        throw PhotosPickerImageDecodeError.unsupportedFormat
    }

    /// Live Photo paired videos and other ISO-BMFF containers must not decode as profile stills.
    private static func looksLikeVideoContainer(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70
    }

    private static func decodeViaImageIO(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 12_000,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            return UIImage(cgImage: thumbnail)
        }

        let loadOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, loadOptions as CFDictionary) else {
            return nil
        }
        let orientation = exifImageOrientation(from: source, index: 0)
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private static func exifImageOrientation(from source: CGImageSource, index: Int) -> UIImage.Orientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32 else {
            return .up
        }
        switch raw {
        case 2: return .upMirrored
        case 3: return .down
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 6: return .right
        case 7: return .rightMirrored
        case 8: return .left
        default: return .up
        }
    }
}

/// Key still for Live Photos and library assets — never the paired video.
private nonisolated enum ProfilePhotoAssetLoader {
    static func loadStillImage(from item: PhotosPickerItem) async -> UIImage? {
        guard let identifier = item.itemIdentifier else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .image else { return nil }

        return await withCheckedContinuation { continuation in
            let resumeOnce = ResumeOnce<UIImage?>(continuation)

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.version = .current

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
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

private nonisolated final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Never>
    private var didResume = false
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}

private nonisolated enum PhotosPickerImageDecodeError: Error, Sendable {
    case emptyData
    case unsupportedFormat
}

enum ImageCropSelectionSupport {
    enum PhotoLoadOutcome: Sendable {
        case success(UIImage)
        case cancelled
        case failed(stage: String)
    }

    static func loadUIImage(from item: PhotosPickerItem?) async -> UIImage? {
        switch await loadUIImageOutcome(from: item) {
        case .success(let image):
            return image
        case .cancelled, .failed:
            return nil
        }
    }

    /// Profile onboarding avatar — PhotoKit key still first, then transferable decode.
    static func loadProfileAvatarUIImageOutcome(from item: PhotosPickerItem?) async -> PhotoLoadOutcome {
        guard let item else {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(stage: "missingItem", errorType: "nilSelection")
#endif
            return .failed(stage: "missingItem")
        }

        if Task.isCancelled {
            return .cancelled
        }

#if DEBUG
        ProfilePhotoDebugLog.transferableLoadStarted()
#endif

        if let assetImage = await ProfilePhotoAssetLoader.loadStillImage(from: item) {
#if DEBUG
            ProfilePhotoDebugLog.transferableLoadCompleted()
#endif
            return finish(assetImage)
        }

        return await loadUIImageOutcome(from: item)
    }

    static func loadUIImageOutcome(from item: PhotosPickerItem?) async -> PhotoLoadOutcome {
        guard let item else {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(stage: "missingItem", errorType: "nilSelection")
#endif
            return .failed(stage: "missingItem")
        }

        if Task.isCancelled {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(stage: "transferableLoad", errorType: "CancellationError")
#endif
            return .cancelled
        }

#if DEBUG
        ProfilePhotoDebugLog.transferableLoadStarted()
#endif

        do {
            let picked = try await item.loadTransferable(type: PickedPhotoTransferable.self)
#if DEBUG
            ProfilePhotoDebugLog.transferableLoadCompleted()
#endif
            guard let picked else {
#if DEBUG
                ProfilePhotoDebugLog.loadFailed(stage: "transferableLoad", errorType: "nilTransferable")
#endif
                return .failed(stage: "transferableLoad")
            }
            return finish(picked.uiImage)
        } catch is CancellationError {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(stage: "transferableLoad", errorType: "CancellationError")
#endif
            return .cancelled
        } catch {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(
                stage: PhotosPickerImageDecoder.Stage.transferableLoad.rawValue,
                errorType: String(describing: type(of: error))
            )
#endif
        }

        if Task.isCancelled {
            return .cancelled
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let decoded = try PhotosPickerImageDecoder.decode(data)
#if DEBUG
                ProfilePhotoDebugLog.transferableLoadCompleted()
#endif
                return finish(decoded)
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(
                stage: PhotosPickerImageDecoder.Stage.dataFallback.rawValue,
                errorType: String(describing: type(of: error))
            )
#endif
        }

#if DEBUG
        ProfilePhotoDebugLog.loadFailed(stage: "decode", errorType: "exhaustedStrategies")
#endif
        return .failed(stage: "decode")
    }

    private static func finish(_ image: UIImage) -> PhotoLoadOutcome {
        let normalized = MediaImageOrientation.normalized(image)
        let size = MediaImageOrientation.pixelSize(of: normalized)
        guard size.width > 0, size.height > 0 else {
#if DEBUG
            ProfilePhotoDebugLog.loadFailed(stage: "normalize", errorType: "zeroDimensions")
#endif
            return .failed(stage: "normalize")
        }
        return .success(normalized)
    }
}
