import Foundation

/// Product analytics sink, Domain defines events, Platform/Data emit them.
nonisolated protocol AnalyticsRepository: Sendable {
    func track(event: String, properties: [String: String]) async
    /// Best-effort delivery before backgrounding (no-op for stubs).
    func flushPendingEvents() async
}

extension AnalyticsRepository {
    func flushPendingEvents() async {}
}
