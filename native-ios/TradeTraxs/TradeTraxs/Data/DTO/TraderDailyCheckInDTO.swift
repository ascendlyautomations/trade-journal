import Foundation

nonisolated enum TraderDailyCheckInDTO {
    static let selectColumns = [
        "id",
        "user_id",
        "check_in_date",
        "sleep_hours",
        "sleep_quality",
        "morning_rating",
        "stress_level",
        "energy_level",
        "focus_level",
        "notes",
        "created_at",
        "updated_at",
    ].joined(separator: ",")

    struct Row: Codable, Sendable {
        var id: String?
        var user_id: String
        var check_in_date: String
        var sleep_hours: Double?
        var sleep_quality: Int?
        var morning_rating: Int?
        var stress_level: Int?
        var energy_level: Int?
        var focus_level: Int?
        var notes: String?
        var created_at: String?
        var updated_at: String?
    }

    struct UpsertBody: Encodable, Sendable {
        var user_id: String
        var check_in_date: String
        var sleep_hours: Double?
        var sleep_quality: Int
        var morning_rating: Int
        var stress_level: Int
        var energy_level: Int
        var focus_level: Int
        var notes: String?
        var updated_at: String
    }
}

nonisolated enum TraderDailyCheckInMapper {
    static func map(_ dto: TraderDailyCheckInDTO.Row) throws -> TraderDailyCheckIn {
        guard let id = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw AppError.domain(.notFound(entity: "trader_daily_check_ins", id: "row"))
        }
        let createdAt = ISO8601.date(from: dto.created_at) ?? Date()
        let updatedAt = ISO8601.date(from: dto.updated_at) ?? createdAt
        let sleepHours = dto.sleep_hours.map { Decimal($0) }
        return TraderDailyCheckIn(
            id: TraderDailyCheckInID(id),
            ownerProfileID: ProfileID(dto.user_id),
            checkInDate: dto.check_in_date,
            sleepHours: sleepHours,
            sleepQuality: dto.sleep_quality,
            morningRating: dto.morning_rating,
            stressLevel: dto.stress_level,
            energyLevel: dto.energy_level,
            focusLevel: dto.focus_level,
            notes: dto.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func upsertBody(
        draft: TraderDailyCheckInDraft,
        profileID: ProfileID
    ) -> TraderDailyCheckInDTO.UpsertBody {
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return TraderDailyCheckInDTO.UpsertBody(
            user_id: profileID.rawValue,
            check_in_date: draft.checkInDate,
            sleep_hours: draft.sleepHours.map { NSDecimalNumber(decimal: $0).doubleValue },
            sleep_quality: draft.sleepQuality,
            morning_rating: draft.morningRating,
            stress_level: draft.stressLevel,
            energy_level: draft.energyLevel,
            focus_level: draft.focusLevel,
            notes: notes.isEmpty ? nil : notes,
            updated_at: ISO8601.string(from: Date())
        )
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
