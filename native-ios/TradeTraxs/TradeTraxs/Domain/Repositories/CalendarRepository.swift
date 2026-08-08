import Foundation

nonisolated protocol CalendarRepository: Sendable {
    func events(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> [CalendarEvent]
    func event(id: CalendarEventID) async throws -> CalendarEvent
    func upsert(_ event: CalendarEvent) async throws -> CalendarEvent
    func delete(id: CalendarEventID) async throws
}
