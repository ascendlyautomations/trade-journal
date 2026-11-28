import SwiftUI

extension BackendV2FeatureFlags {
    static var recordsCreatorContentViews: Bool {
        isEnabled(.feedRotatingRank) || isEnabled(.profileInsights)
    }
}

struct CreatorContentImpressionModifier: ViewModifier {
    let contentKind: String
    let contentID: String
    let surface: String
    @State private var didRecord = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                recordOnceIfNeeded()
            }
    }

    private func recordOnceIfNeeded() {
        guard !didRecord else { return }
        guard BackendV2FeatureFlags.recordsCreatorContentViews else { return }
        didRecord = true
        FeedImpressionCoordinator.shared.trackVisibleContent(
            kind: contentKind,
            contentID: contentID,
            surface: surface
        )
    }
}

extension View {
    func creatorContentImpressionTracked(
        contentKind: String,
        contentID: String,
        surface: String
    ) -> some View {
        modifier(
            CreatorContentImpressionModifier(
                contentKind: contentKind,
                contentID: contentID,
                surface: surface
            )
        )
    }
}

extension InteractionTarget {
    var creatorRPCContentKind: String? {
        switch kind {
        case .feedPost: return "post"
        case .profilePost: return "profile_post"
        case .reel: return "reel"
        case .achievement: return "achievement_post"
        case .trade, .story: return nil
        }
    }

    func recordCreatorImpression(surface: String) {
        guard let kind = creatorRPCContentKind else { return }
        FeedImpressionCoordinator.shared.trackVisibleContent(
            kind: kind,
            contentID: id,
            surface: surface
        )
    }
}