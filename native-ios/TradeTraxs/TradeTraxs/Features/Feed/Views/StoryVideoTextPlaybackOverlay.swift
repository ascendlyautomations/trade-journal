import SwiftUI

/// Draws persisted story text above video playback. The layer stays mounted while the player loops, pauses, or buffers.
struct StoryVideoTextPlaybackOverlay: View {
    let overlays: [StoryTextOverlayRecord]
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            ForEach(overlays, id: \.id) { record in
                StoryTextOverlayView(
                    overlay: record.storyTextOverlay(),
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
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}