import AVFoundation
import Foundation
import Photos
import PhotosUI
import SwiftUI

/// Shared gate for the 90-second upload limit. Rejects before encode or upload.
enum VideoUploadDurationValidation {
    static let alertTitle = "Video Too Long"
    static let alertMessage = "This video is too long to upload. Please choose a video under 90 seconds."
    static let chooseAnotherTitle = "Choose Another Video"

    struct TooLong: Error {}

    /// Matches ``MediaVideoPreparation`` (`ceil` seconds must be <= 90).
    static func exceedsUploadLimit(durationSeconds: Double) -> Bool {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return false }
        return Int(ceil(durationSeconds)) > MediaVideoPreparation.maxDurationSeconds
    }

    /// Photo library duration when the picker item is a video. Nil when unavailable.
    static func photoLibraryDurationSeconds(for item: PhotosPickerItem) -> Double? {
        guard let identifier = item.itemIdentifier else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .video else { return nil }
        let duration = asset.duration
        guard duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    /// When PhotoKit duration is available, rejects over-limit picks before any provider load or file copy.
    static func throwIfPhotoLibraryExceedsReelUploadLimit(_ item: PhotosPickerItem) throws {
        guard let seconds = photoLibraryDurationSeconds(for: item) else { return }
        if exceedsUploadLimit(durationSeconds: seconds) {
            throw TooLong()
        }
    }

    /// Metadata-only duration gate for file URLs — before copy, transcode, or thumbnail work.
    static func validateReelUploadDuration(at fileURL: URL) async throws {
        try await validateFileBeforeUpload(at: fileURL)
    }

    static func durationSeconds(at fileURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw AppError.unknown(message: "Couldn't read this video.")
        }
        return seconds
    }

    /// Reads the file timeline and throws ``TooLong`` before any encode or upload.
    /// Unreadable files are left for the existing preparation errors.
    static func validateFileBeforeUpload(at fileURL: URL) async throws {
        guard let seconds = try? await durationSeconds(at: fileURL) else { return }
        if exceedsUploadLimit(durationSeconds: seconds) {
            throw TooLong()
        }
    }

    static func isTooLong(_ error: Error) -> Bool {
        if error is TooLong { return true }
        if let failure = error as? VideoPreparationFailure, failure == .durationExceeded {
            return true
        }
        if case .unknown(let message) = error as? AppError,
           message == MediaVideoPreparation.durationLimitMessage {
            return true
        }
        return false
    }
}

private struct VideoTooLongAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onChooseAnother: () -> Void

    func body(content: Content) -> some View {
        content.alert(VideoUploadDurationValidation.alertTitle, isPresented: $isPresented) {
            Button(VideoUploadDurationValidation.chooseAnotherTitle) {
                onChooseAnother()
            }
            .accessibilityIdentifier("videoUpload.tooLong.chooseAnother")
        } message: {
            Text(VideoUploadDurationValidation.alertMessage)
        }
    }
}

extension View {
    func videoTooLongAlert(
        isPresented: Binding<Bool>,
        onChooseAnother: @escaping () -> Void = {}
    ) -> some View {
        modifier(VideoTooLongAlertModifier(isPresented: isPresented, onChooseAnother: onChooseAnother))
    }
}
