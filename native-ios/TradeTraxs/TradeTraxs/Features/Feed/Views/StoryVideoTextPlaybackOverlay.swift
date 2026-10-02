import SwiftUI

/// Draws persisted story text above video playback. The layer stays mounted while the player loops, pauses, or buffers.
struct StoryVideoTextPlaybackOverlay: View {
    let overlays: [StoryTextOverlayRecord]
    let videoPixelSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                ForEach(overlays, id: \.id) { record in
                    StoryTextOverlayView(
                        overlay: record.positionedForPlayback(
                            videoPixelSize: videoPixelSize,
                            viewerSize: canvasSize
                        ),
                        canvasSize: canvasSize,
                        isSelected: false,
                        transformsEnabled: false,
                        onSelect: {},
                        onMove: { _ in },
                        onScale: { _ in },
                        onRotation: { _ in },
                        onEdit: {}
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
