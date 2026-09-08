import AVFoundation
import SwiftUI

/// Story media surface — aspect-fill image or inline video from ``StoryPlaybackController``.
struct StoryPlaybackMediaView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    let player: AVPlayer?
    let isVideo: Bool
    var accessibilityIdentifier: String = "feed.story.media"

    var body: some View {
        Group {
            if isVideo, let player {
                FeedInlineVideoSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StoryAspectFillMediaView(
                    reference: reference,
                    imagePipeline: imagePipeline,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            }
        }
        .clipped()
    }
}
