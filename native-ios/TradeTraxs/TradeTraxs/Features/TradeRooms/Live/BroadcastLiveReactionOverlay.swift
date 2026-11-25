import Combine
import SwiftUI

/// Instagram-style floating emoji over the live video layer.
struct BroadcastLiveReactionOverlay: View {
    let reactions: [BroadcastFloatingReaction]

    @State private var active: [ActiveReaction] = []

    private struct ActiveReaction: Identifiable {
        let id: String
        let emoji: String
        let originX: CGFloat
        let startedAt: Date
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(active) { item in
                    TimelineView(.animation) { timeline in
                        let progress = min(
                            1,
                            max(0, timeline.date.timeIntervalSince(item.startedAt) / 2.8)
                        )
                        Text(item.emoji)
                            .font(.system(size: 34))
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                            .opacity(1 - progress)
                            .scaleEffect(0.85 + (1 - progress) * 0.2)
                            .position(
                                x: item.originX * proxy.size.width,
                                y: proxy.size.height * (0.82 - progress * 0.45)
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: reactions.last?.id) { _, _ in
            guard let latest = reactions.last else { return }
            if active.contains(where: { $0.id == latest.id }) { return }
            active = (active + [
                ActiveReaction(
                    id: latest.id,
                    emoji: latest.emoji,
                    originX: latest.originX,
                    startedAt: Date()
                )
            ]).suffix(24)
        }
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { now in
            active.removeAll { now.timeIntervalSince($0.startedAt) > 3.1 }
        }
    }
}