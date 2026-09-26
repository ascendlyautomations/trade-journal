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
    var onReadyForDisplayChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(clipID: clipID, onReadyForDisplayChange: onReadyForDisplayChange)
    }

    func makeUIView(context: Context) -> FeedPlayerLayerView {
        let view = FeedPlayerLayerView()
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .clear
        view.isOpaque = false
        view.playerLayer.isOpaque = false
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.player = player
        context.coordinator.bindReadyForDisplayObservation(to: view.playerLayer)
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
        context.coordinator.onReadyForDisplayChange = onReadyForDisplayChange

        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            context.coordinator.bindReadyForDisplayObservation(to: uiView.playerLayer)
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
        uiView.backgroundColor = .clear
        uiView.isOpaque = false
        uiView.playerLayer.isOpaque = false
        uiView.playerLayer.backgroundColor = UIColor.clear.cgColor
        uiView.onDidLayout = { [weak coordinator = context.coordinator] layerView in
            coordinator?.logLayoutIfNeeded(
                layerView: layerView,
                containerSize: containerSize,
                gravity: videoGravity
            )
        }
        if uiView.bounds.size != containerSize, containerSize.width > 1, containerSize.height > 1 {
            uiView.setNeedsLayout()
        }
        context.coordinator.bindReadyForDisplayObservation(to: uiView.playerLayer)
    }

    final class Coordinator {
        let clipID: String
        var containerSize: CGSize = .zero
        var onReadyForDisplayChange: ((Bool) -> Void)?
        private var lastLoggedBounds: CGRect = .zero
        private var metadataLoadGeneration: UInt64 = 0
        private var readyForDisplayObservation: NSKeyValueObservation?

        init(clipID: String, onReadyForDisplayChange: ((Bool) -> Void)?) {
            self.clipID = clipID
            self.onReadyForDisplayChange = onReadyForDisplayChange
        }

        func bindReadyForDisplayObservation(to layer: AVPlayerLayer) {
            readyForDisplayObservation?.invalidate()
            readyForDisplayObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async {
                    self?.onReadyForDisplayChange?(ready)
                }
            }
        }

        deinit {
            readyForDisplayObservation?.invalidate()
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
            guard let item = playerLayer.player?.currentItem else { return }
            let asset = item.asset
            let itemToken = ObjectIdentifier(item)
            metadataLoadGeneration &+= 1
            let generation = metadataLoadGeneration

            let presentationSize = item.presentationSize
            let swiftUIContainer = containerSize
            let uiViewBounds = bounds
            let playerLayerFrame = playerLayer.frame
            let videoRect = playerLayer.videoRect
            let gravityLabel = gravity == .resizeAspectFill ? "aspectFill" : "aspectFit"
            let clipID = self.clipID

            Task {
                let trackMetadata = await Self.loadVideoTrackMetadata(asset: asset)
                await MainActor.run {
                    guard generation == self.metadataLoadGeneration else { return }
                    guard playerLayer.player?.currentItem.map(ObjectIdentifier.init) == itemToken else {
                        return
                    }
                    InlineClipRenderFrameDiagnostics.log(
                        clipID: clipID,
                        swiftUIContainer: swiftUIContainer,
                        uiViewBounds: uiViewBounds,
                        playerLayerFrame: playerLayerFrame,
                        videoRect: videoRect,
                        gravity: gravityLabel,
                        presentationSize: presentationSize.width > 0 ? presentationSize : nil,
                        naturalSize: trackMetadata?.naturalSize,
                        preferredTransform: trackMetadata?.transformSummary
                    )
                }
            }
        }

        private struct VideoTrackMetadata: Sendable {
            let naturalSize: CGSize
            let transformSummary: String
        }

        private static func loadVideoTrackMetadata(asset: AVAsset) async -> VideoTrackMetadata? {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
            guard let naturalSize = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform)
            else { return nil }
            let transformSummary = String(
                format: "a=%.2f,b=%.2f,c=%.2f,d=%.2f,tx=%.0f,ty=%.0f",
                transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty
            )
            return VideoTrackMetadata(naturalSize: naturalSize, transformSummary: transformSummary)
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
