import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared PhotosPicker filters — keep upload surfaces from exposing the wrong library media.
enum MediaPickerPolicy: Sendable {
    /// Trades, posts, achievements, chat, room avatars, etc.
    case imageOnly
    /// Profile avatars — still images only (no Live Photo motion in the picker).
    case profilePhoto
    /// Clips / reel uploads.
    case videoOnly
    /// Stories — still image or short video.
    case storyMedia

    var matching: PHPickerFilter {
        switch self {
        case .imageOnly:
            return .images
        case .profilePhoto:
            return .any(of: [.images, .not(.livePhotos)])
        case .videoOnly:
            return .videos
        case .storyMedia:
            return .any(of: [.images, .videos])
        }
    }
}

extension PhotosPickerItem {
    var isVideoPickerItem: Bool {
        supportedContentTypes.contains { type in
            type.conforms(to: .movie)
                || type.conforms(to: .mpeg4Movie)
                || type.conforms(to: .quickTimeMovie)
                || type.conforms(to: .video)
        }
    }
}
