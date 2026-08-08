import Foundation

nonisolated struct DefaultAnalyticsRepository: AnalyticsRepository {
    private let supabase: SupabaseInfrastructure?

    init(supabase: SupabaseInfrastructure? = nil) {
        self.supabase = supabase
    }

    func track(event: String, properties: [String: String]) async {
        guard let supabase, supabase.client.isConfigured else { return }
        struct Body: Encodable, Decodable {
            var name: String?
            var properties: [String: String]?
            var occurred_at: String?
        }
        let body = Body(
            name: event,
            properties: properties,
            occurred_at: ISO8601.string(from: Date())
        )
        _ = try? await supabase.database.insert(
            body,
            into: "analytics_events",
            returning: Body.self
        )
    }
}
