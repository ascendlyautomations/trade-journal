import AVFoundation
import SwiftUI
import UIKit

final class FeedPlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var onDidLayout: ((FeedPlayerLayerView) -> Void)?

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer")
        }
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        onDidLayout?(self)
    }
}

/// Lightweight inline feed video surface — fills SwiftUI-assigned bounds; UIKit does not recompute height.
struct FeedInlineVideoSurface: UIViewRepresentable {
    var clipID: String = ""
    let player: AVPlayer?
    var containerSize: CGSize = .zero
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeCoordinator() -> Coordinator {
        Coordinator(clipID: clipID)
    }

    func makeUIView(context: Context) -> FeedPlayerLayerView {
        let view = FeedPlayerLayerView()
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .clear
        view.onDidLayout = { [weak coordinator = context.coordinator] layerView in
            coordinator?.logLayoutIfNeeded(
                layerView: layerView,
                containerSize: containerSize,
                gravity: videoGravity
            )
        }
        return view
    }

    func updateUIView(_ uiView: FeedPlayerLayerView, context: Context) {
        context.coordinator.containerSize = containerSize

        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
        uiView.onDidLayout = { [weak coordinator = context.coordinator] layerView in
            coordinator?.logLayoutIfNeeded(
                layerView: layerView,
                containerSize: containerSize,
                gravity: videoGravity
            )
        }
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }

    final class Coordinator {
        let clipID: String
        var containerSize: CGSize = .zero
        private var lastLoggedBounds: CGRect = .zero

        init(clipID: String) {
            self.clipID = clipID
        }

        func logLayoutIfNeeded(
            layerView: FeedPlayerLayerView,
            containerSize: CGSize,
            gravity: AVLayerVideoGravity
        ) {
            let bounds = layerView.bounds
            guard bounds.width > 1, bounds.height > 1 else { return }
            guard abs(bounds.width - lastLoggedBounds.width) > 1
                || abs(bounds.height - lastLoggedBounds.height) > 1
            else { return }
            lastLoggedBounds = bounds

            let playerLayer = layerView.playerLayer
            let item = playerLayer.player?.currentItem
            let presentationSize = item?.presentationSize ?? .zero
            var naturalSize: CGSize?
            var transformSummary: String?
            if let track = item?.asset.tracks(withMediaType: .video).first {
                naturalSize = track.naturalSize
                let transform = track.preferredTransform
                transformSummary = String(
                    format: "a=%.2f,b=%.2f,c=%.2f,d=%.2f,tx=%.0f,ty=%.0f",
                    transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty
                )
            }

            InlineClipRenderFrameDiagnostics.log(
                clipID: clipID,
                swiftUIContainer: containerSize,
                uiViewBounds: bounds,
                playerLayerFrame: playerLayer.frame,
                videoRect: playerLayer.videoRect,
                gravity: gravity == .resizeAspectFill ? "aspectFill" : "aspectFit",
                presentationSize: presentationSize.width > 0 ? presentationSize : nil,
                naturalSize: naturalSize,
                preferredTransform: transformSummary
            )
        }
    }
}

struct FeedClipMediaView: View {
    let feedItemID: String
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    let onTogglePlayPause: () -> Void
    let onDoubleTapLike: () -> Void

    var body: some View {
        VideoFeedInlineContainer(
            reel: reel,
            feedItemID: feedItemID,
            presentation: playbackCoordinator.presentation(for: reel.id),
            imagePipeline: imagePipeline,
            playbackCoordinator: playbackCoordinator
        ) {
            if playbackCoordinator.shouldShowPlayIndicator(for: reel.id) {
                ExperienceIcon(icon: .play, size: .lg, color: .white)
                    .padding(ExperienceSpacing.md)
                    .shadow(radius: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .experienceDoubleTapLike(
                        onSingleTap: onTogglePlayPause,
                        perform: onDoubleTapLike
                    )

                Button {
                    playbackCoordinator.toggleMute()
                } label: {
                    Image(systemName: playbackCoordinator.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playbackCoordinator.isMuted ? "Unmute clip" : "Mute clip")
                .padding(ExperienceSpacing.md)
                .zIndex(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .feedInlineClipVisibilityReporting(
            reel: reel,
            playbackCoordinator: playbackCoordinator
        )
    }
}
