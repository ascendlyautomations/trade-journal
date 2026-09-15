import AVFoundation
import SwiftUI

/// Story media surface — aspect-fill image or inline video from ``StoryPlaybackController``.
struct StoryPlaybackMediaView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    let objectStorage: any ObjectStorageProviding
    let player: AVPlayer?
    let isVideo: Bool
    var accessibilityIdentifier: String = "feed.story.media"

    @State private var isDisplayingVideoFrame = false

    var body: some View {
        ZStack {
            if isVideo, let reference, reference.kind == .video {
                FeedClipPosterImage(
                    thumbnail: nil,
                    video: reference,
                    imagePipeline: imagePipeline,
                    objectStorage: objectStorage,
                    contentMode: .fill,
                    mediaBucket: .stories
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isDisplayingVideoFrame ? 0 : 1)
                .allowsHitTesting(false)
            }

            if isVideo, let player {
                FeedInlineVideoSurface(
                    player: player,
                    videoGravity: .resizeAspectFill,
                    onReadyForDisplayChange: { ready in
                        isDisplayingVideoFrame = ready
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isVideo {
                StoryAspectFillMediaView(
                    reference: reference,
                    imagePipeline: imagePipeline,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            }
        }
        .clipped()
        .onChange(of: player?.currentItem) { _, _ in
            isDisplayingVideoFrame = false
        }
    }
}
