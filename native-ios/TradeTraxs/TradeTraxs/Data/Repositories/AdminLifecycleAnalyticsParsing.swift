import Foundation

nonisolated enum AdminLifecycleAnalyticsParsing {
    static func parseBundle(from data: Data) throws -> AdminLifecycleAnalyticsBundle {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AdminUsageAnalyticsError.invalidResponse
        }
        let meta = root["meta"] as? [String: Any] ?? [:]
        let activation = root["userGrowthActivation"] as? [String: Any] ?? [:]
        let traxs = root["traxsProConversion"] as? [String: Any] ?? [:]
        let retention = root["retentionChurn"] as? [String: Any] ?? [:]
        let session = retention["sessionRetention"] as? [String: Any] ?? [:]

        return AdminLifecycleAnalyticsBundle(
            seriesDays: max(1, AdminUsageAnalyticsParsing.int(root["seriesDays"])),
            activationStages: parseStages(activation["stages"]),
            traxsProStages: parseStages(traxs["stages"]),
            sessionD1Rate: optionalDouble(session["d1Rate"]),
            sessionD7Rate: optionalDouble(session["d7Rate"]),
            sessionD1MatureCohortSize: AdminUsageAnalyticsParsing.int(session["d1MatureCohortSize"]),
            sessionRetentionInsufficientData: session["insufficientData"] as? Bool ?? false,
            notes: (meta["notes"] as? [String]) ?? []
        )
    }

    private static func parseStages(_ raw: Any?) -> [AdminLifecycleFunnelStage] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.map { row in
            AdminLifecycleFunnelStage(
                id: row["id"] as? String ?? "",
                label: row["label"] as? String ?? "",
                count: AdminUsageAnalyticsParsing.int(row["count"])
            )
        }
    }

    private static func optionalDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}