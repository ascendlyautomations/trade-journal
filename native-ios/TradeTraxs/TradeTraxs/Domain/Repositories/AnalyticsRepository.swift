import Foundation

/// Product analytics sink — Domain defines events, Platform/Data emit them.
nonisolated protocol AnalyticsRepository: Sendable {
    func track(event: String, properties: [String: String]) async
}
