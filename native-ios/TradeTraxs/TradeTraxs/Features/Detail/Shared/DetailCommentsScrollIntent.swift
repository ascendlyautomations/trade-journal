import SwiftUI

/// Navigation intent: after opening a detail destination, scroll the comments block into view.
enum DetailCommentsScrollIntent: Hashable {
    case trade(TradeID)
    case post(PostID)
    case achievement(AchievementID)
}

extension DetailCommentsScrollIntent {
    var storageKey: String {
        switch self {
        case .trade(let id): return "trade:\(id.rawValue)"
        case .post(let id): return "post:\(id.rawValue)"
        case .achievement(let id): return "achievement:\(id.rawValue)"
        }
    }
}

/// Scrolls to the comments anchor once detail content is on-screen, retries while async layout settles.
struct DetailCommentsScrollOnOpenModifier: ViewModifier {
    let intent: DetailCommentsScrollIntent
    let anchorID: String
    let isContentReady: Bool
    let contentRevealed: Bool
    let detailCache: DetailPresentationCache
    let scrollProxy: ScrollViewProxy
    let reduceMotion: Bool

    @State private var pendingScroll = false
    @State private var scrollTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if detailCache.consumeScrollToComments(intent) {
                    pendingScroll = true
                    scheduleScrollIfReady()
                }
            }
            .onChange(of: isContentReady) { _, _ in scheduleScrollIfReady() }
            .onChange(of: contentRevealed) { _, _ in scheduleScrollIfReady() }
            .onDisappear {
                scrollTask?.cancel()
                scrollTask = nil
            }
    }

    private func scheduleScrollIfReady() {
        guard pendingScroll, isContentReady, contentRevealed else { return }
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            let animation = ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
            for attempt in 0 ..< 7 {
                if Task.isCancelled { return }
                let delayNanos = UInt64(48_000_000 + attempt * 28_000_000)
                try? await Task.sleep(nanoseconds: delayNanos)
                withAnimation(animation) {
                    scrollProxy.scrollTo(anchorID, anchor: .top)
                }
            }
            pendingScroll = false
        }
    }
}

extension View {
    func detailCommentsScrollOnOpen(
        intent: DetailCommentsScrollIntent,
        anchorID: String,
        isContentReady: Bool,
        contentRevealed: Bool,
        detailCache: DetailPresentationCache,
        scrollProxy: ScrollViewProxy,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            DetailCommentsScrollOnOpenModifier(
                intent: intent,
                anchorID: anchorID,
                isContentReady: isContentReady,
                contentRevealed: contentRevealed,
                detailCache: detailCache,
                scrollProxy: scrollProxy,
                reduceMotion: reduceMotion
            )
        )
    }
}