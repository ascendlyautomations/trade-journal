import LiveKit
import SwiftUI

struct LiveKitBroadcastVideoView: UIViewRepresentable {
    var track: VideoTrack?

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
    }
}
