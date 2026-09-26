import AVFoundation
import SwiftUI

/// Inline Feed clip layout — compact capped media region; full video visible via aspectFit.
struct VideoFeedInlineContainer<Overlay: View>: View {
    let reel: Reel
    var feedItemID: String? = nil
    let presentation: VideoPresentationInfo?
    let imagePipeline: any ImagePipeline
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack {
            Color.clear

            FeedClipPosterImage(
                thumbnail: reel.thumbnail,
                video: reel.video,
                imagePipeline: imagePipeline,
                objectStorage: playbackCoordinator.objectStorage,
                feedItemID: feedItemID ?? reel.id.rawValue,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(playbackCoordinator.shouldHidePoster(for: reel.id) ? 0 : 1)
            .allowsHitTesting(false)

            if let frozenFrame = playbackCoordinator.frozenFrame(for: reel.id),
               !playbackCoordinator.shouldShowLivePlayer(for: reel.id)
            {
                Image(uiImage: frozenFrame)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if playbackCoordinator.shouldShowLivePlayer(for: reel.id),
               let player = playbackCoordinator.player(for: reel.id)
            {
                FeedInlineVideoSurface(
                    clipID: reel.id.rawValue,
                    player: player,
                    containerSize: fittedMediaSize,
                    videoGravity: resolvedGravity,
                    onReadyForDisplayChange: { ready in
                        if ready {
                            playbackCoordinator.noteVideoReadyForDisplay(reel.id)
                        } else {
                            playbackCoordinator.noteVideoDisplayLost(reel.id)
                        }
                    }
                )
                .frame(width: fittedMediaSize.width, height: fittedMediaSize.height)
                .allowsHitTesting(false)
            }

            overlay()
        }
        .frame(maxWidth: .infinity)
        .frame(height: layoutMetrics.height)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            logPresentationOnce()
        }
        .onChange(of: layoutMetrics.height) { _, _ in
            logPresentationOnce()
        }
    }

    private var resolvedGravity: AVLayerVideoGravity {
        presentation?.playerGravity(for: .feedInline) ?? .resizeAspect
    }

    /// Aspect-fit video box inside the capped inline region.
    /// The container stays `layoutMetrics`; only the player layer hugs the video
    /// so letterbox area is the parent card instead of the player’s black fill.
    private var fittedMediaSize: CGSize {
        let container = layoutMetrics
        let aspect = presentation?.aspectRatio ?? FeedInlineClipLayout.placeholderAspectRatio
        let safeAspect = max(aspect, 0.01)
        let containerAspect = container.width / max(container.height, 1)
        if safeAspect >= containerAspect {
            return CGSize(width: container.width, height: container.width / safeAspect)
        }
        return CGSize(width: container.height * safeAspect, height: container.height)
    }

    private var layoutMetrics: CGSize {
        let width = UIScreen.main.bounds.width
        if let presentation {
            return presentation.feedInlineContainerSize(
                containerWidth: width,
                screenBounds: UIScreen.main.bounds
            )
        }
        return FeedInlineClipLayout.containerSize(
            containerWidth: width,
            videoAspectRatio: FeedInlineClipLayout.placeholderAspectRatio,
            screenBounds: UIScreen.main.bounds
        )
    }

    @State private var didLogPresentation = false

    private func logPresentationOnce() {
        guard !didLogPresentation, let presentation else { return }
        didLogPresentation = true
        let width = UIScreen.main.bounds.width
        let metrics = presentation.feedInlineContainerSize(
            containerWidth: width,
            screenBounds: UIScreen.main.bounds
        )
        InlineClipPresentationDiagnostics.log(
            clipID: reel.id.rawValue,
            sourceSize: "\(Int(presentation.rawSize.width))x\(Int(presentation.rawSize.height))",
            orientedSize: "\(Int(presentation.orientedSize.width))x\(Int(presentation.orientedSize.height))",
            aspectRatio: presentation.aspectRatio,
            containerWidth: metrics.width,
            containerHeight: metrics.height,
            gravity: presentation.gravityLabel(for: .feedInline)
        )
    }
}

/// Poster frame for inline / pager clip surfaces.
struct FeedClipPosterImage: View {
    let thumbnail: MediaReference?
    let video: MediaReference
    let imagePipeline: any ImagePipeline
    let objectStorage: any ObjectStorageProviding
    var feedItemID: String? = nil
    var contentMode: ContentMode = .fill
    var mediaBucket: StorageBucket = .reels
    var allowsVideoFrameExtraction: Bool = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @State private var displayImage: UIImage?

    var body: some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    colors.fillPrimary
                    ExperienceIcon(icon: .photo, size: .xl, color: colors.tertiaryText)
                }
            }
        }
        .task(id: posterTaskID) {
            await loadDisplayImage()
        }
    }

    private var posterTaskID: String {
        "\(video.id)|\(thumbnail?.id ?? "")"
    }

    private func loadDisplayImage() async {
        let itemID = feedItemID ?? video.id
        let scale = displayScale
        let image = await VideoPosterFrameLoader.loadPoster(
            thumbnail: thumbnail,
            video: video,
            imagePipeline: imagePipeline,
            storage: objectStorage,
            bucket: mediaBucket,
            displayScale: scale,
            allowsVideoFrameExtraction: allowsVideoFrameExtraction
        )
        guard !Task.isCancelled else { return }
        displayImage = image
        if image != nil {
            FeedMediaReadyProbe.log(itemID: itemID, kind: "clip-thumbnail", source: "poster")
            if let feedItemID {
                FeedImageViewportReadiness.noteMediaResolved(entryID: feedItemID, outcome: .loaded)
            }
        } else if let feedItemID {
            FeedImageViewportReadiness.noteMediaResolved(entryID: feedItemID, outcome: .failed)
        }
    }
}
