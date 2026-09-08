import Foundation

nonisolated enum FeedFilterCacheSource: String, Sendable {
    case none
    case exactFilterCache
    case siblingFilterCache
    case networkRefresh
}

#if DEBUG
nonisolated enum FeedFilterCacheProbe {
    static func logHydrate(
        filter: FeedContentFilter,
        scope: FeedScope,
        source: FeedFilterCacheSource,
        cachedCount: Int,
        knownEmpty: Bool
    ) {
        print(
            "[Feed] filter.hydrate filter=\(filter.rawValue) scope=\(scope.rawValue) " +
            "source=\(source.rawValue) cachedCount=\(cachedCount) knownEmpty=\(knownEmpty)"
        )
    }

    static func logNetworkRefresh(
        filter: FeedContentFilter,
        scope: FeedScope,
        resultCount: Int,
        knownEmpty: Bool
    ) {
        print(
            "[Feed] filter.networkRefresh filter=\(filter.rawValue) scope=\(scope.rawValue) " +
            "resultCount=\(resultCount) knownEmpty=\(knownEmpty)"
        )
    }
}
#else
nonisolated enum FeedFilterCacheProbe {
    static func logHydrate(
        filter: FeedContentFilter,
        scope: FeedScope,
        source: FeedFilterCacheSource,
        cachedCount: Int,
        knownEmpty: Bool
    ) {}

    static func logNetworkRefresh(
        filter: FeedContentFilter,
        scope: FeedScope,
        resultCount: Int,
        knownEmpty: Bool
    ) {}
}
#endif
