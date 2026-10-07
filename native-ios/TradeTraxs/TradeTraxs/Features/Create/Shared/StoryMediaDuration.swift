import AVFoundation
import Foundation
import PhotosUI
import SwiftUI

/// Story video duration guard — uses the selected asset's timeline, not picker metadata alone.
enum StoryMediaDuration {
    static let maxVideoDurationSeconds = 10
    static let durationExceededMessage = "Story videos can be up to 10 seconds."

    /// PhotoKit duration when available — preflight before loading the full movie provider.
    static func photoLibraryDurationSeconds(for item: PhotosPickerItem) -> Double? {
        VideoUploadDurationValidation.photoLibraryDurationSeconds(for: item)
    }

    static func exceedsLimit(durationSeconds: Double) -> Bool {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return false }
        return durationSeconds > Double(maxVideoDurationSeconds) + 0.05
    }

    /// Returns duration in seconds when valid; throws ``durationExceededMessage`` when over the cap.
    static func validatedDurationSeconds(at url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw AppError.unknown(message: "Couldn't read this video.")
        }
        if seconds > Double(maxVideoDurationSeconds) + 0.05 {
            throw AppError.unknown(message: durationExceededMessage)
        }
        return seconds
    }
}
