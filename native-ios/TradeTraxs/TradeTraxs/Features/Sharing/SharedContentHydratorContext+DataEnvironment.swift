import Foundation

extension SharedContentHydrator.Context {
    @MainActor
    static func make(
        data: DataEnvironment,
        viewerID: ProfileID?
    ) -> SharedContentHydrator.Context {
        SharedContentHydrator.Context(
            detailCache: data.detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: viewerID,
            tradesRepo: data.trades,
            feedRepo: data.feed,
            achievementsRepo: data.achievements,
            profilesRepo: data.profiles
        )
    }
}
