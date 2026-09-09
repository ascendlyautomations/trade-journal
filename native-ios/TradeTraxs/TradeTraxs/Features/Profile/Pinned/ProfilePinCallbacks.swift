import Foundation

/// Owner-only pin actions passed from ``ProfileScreenViewModel`` into section containers.
struct ProfilePinCallbacks {
    var isPinned: (ProfilePinnedContentType, String) -> Bool
    var requestPin: (ProfilePinnedContentType, String, ProfilePinnedPreview) -> Void
}
