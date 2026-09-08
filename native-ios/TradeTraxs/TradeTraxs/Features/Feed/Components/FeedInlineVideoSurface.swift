import AVFoundation
import SwiftUI
import UIKit

final class FeedPlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer")
        }
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

/// Lightweight inline feed video surface — reuses a shared ``AVPlayer`` from the coordinator.
///
/// Must be overlaid on a SwiftUI view that defines the media frame (e.g. ``AspectFitMediaView``).
/// Without an explicit layout anchor, ``UIViewRepresentable`` has no intrinsic size and the
/// player layer renders at zero bounds.
struct FeedInlineVideoSurface: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> FeedPlayerLayerView {
        let view = FeedPlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }

    func updateUIView(_ uiView: FeedPlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.setNeedsLayout()
    }
}

struct FeedClipMediaView: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let playbackCoordinator: FeedVideoPlaybackCoordinator

    var body: some View {
        AspectFitMediaView(
            reference: reel.thumbnail ?? reel.video,
            purpose: .reelThumbnail,
            imagePipeline: imagePipeline,
            accessibilityIdentifier: "feed.clip.media",
            emptyIcon: .video,
            allowsFullResolutionViewer: false,
            showsPlaceholderWhenUnavailable: false
        )
        .overlay {
            if playbackCoordinator.isActive(reel.id),
               let player = playbackCoordinator.player(for: reel)
            {
                FeedInlineVideoSurface(player: player)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if playbackCoordinator.shouldShowPlayIndicator(for: reel.id) {
                ExperienceIcon(icon: .play, size: .lg, color: .white)
                    .padding(ExperienceSpacing.md)
                    .shadow(radius: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
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
        }
        .clipped()
        .onAppear {
            playbackCoordinator.preparePlayback(for: reel)
            if playbackCoordinator.isActive(reel.id) {
                playbackCoordinator.syncPlayback(for: reel.id)
            }
        }
        .onScrollVisibilityChange(threshold: 0.55) { visible in
            playbackCoordinator.setClipVisible(reel.id, visible: visible)
        }
    }
}
