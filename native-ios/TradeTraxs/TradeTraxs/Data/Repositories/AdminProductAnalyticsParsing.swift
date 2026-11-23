import Foundation

nonisolated enum AdminProductAnalyticsParsing {
    static func parseBundle(from data: Data) throws -> AdminProductAnalyticsBundle {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AdminUsageAnalyticsError.invalidResponse
        }

        let metaObject = root["meta"] as? [String: Any] ?? [:]
        let overviewObject = root["overview"] as? [String: Any] ?? [:]
        let growthObject = root["growth"] as? [String: Any] ?? [:]
        let retentionObject = root["retention"] as? [String: Any] ?? [:]
        let tradingObject = root["trading"] as? [String: Any] ?? [:]
        let socialObject = root["social"] as? [String: Any] ?? [:]
        let featuresObject = root["features"] as? [String: Any] ?? [:]
        let previewObject = root["traxsProPreview"] as? [String: Any] ?? [:]
        let funnelObject = previewObject["funnelTotals"] as? [String: Any] ?? [:]
        let importObject = tradingObject["importTotalsInPeriod"] as? [String: Any] ?? [:]

        let notes = (metaObject["notes"] as? [String]) ?? []
        let seriesDays = max(1, AdminUsageAnalyticsParsing.int(root["seriesDays"]))
        let topFeatures = parseFeatureRows(featuresObject["topFeatures"])

        return AdminProductAnalyticsBundle(
            seriesDays: seriesDays,
            meta: AdminProductAnalyticsMeta(
                productTrackingStartDate: metaObject["productTrackingStartDate"] as? String,
                productEngagementAvailable: metaObject["productEngagementAvailable"] as? Bool ?? false,
                retentionMetricsAvailable: metaObject["retentionMetricsAvailable"] as? Bool ?? false,
                previewFunnelAvailable: metaObject["previewFunnelAvailable"] as? Bool ?? false,
                notes: notes
            ),
            overview: AdminProductAnalyticsOverview(
                totalUsers: AdminUsageAnalyticsParsing.int(overviewObject["totalUsers"]),
                newSignupsToday: AdminUsageAnalyticsParsing.int(overviewObject["newSignupsToday"]),
                productDau: optionalInt(overviewObject["productDau"]),
                productWau: optionalInt(overviewObject["productWau"]),
                productMau: optionalInt(overviewObject["productMau"]),
                dauMauRatio: optionalDouble(overviewObject["dauMauRatio"])
            ),
            retentionD1Rate: optionalDouble(retentionObject["d1Rate"]),
            retentionD7Rate: optionalDouble(retentionObject["d7Rate"]),
            retentionD30Rate: optionalDouble(retentionObject["d30Rate"]),
            cohortSampleSignups: AdminUsageAnalyticsParsing.int(retentionObject["cohortSampleSignups"]),
            retentionInsufficientData: retentionObject["insufficientData"] as? Bool ?? false,
            retentionD1MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d1MatureCohortSize"]),
            retentionD7MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d7MatureCohortSize"]),
            retentionD30MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d30MatureCohortSize"]),
            tradesPerActiveTraderLatestDay: optionalDouble(tradingObject["tradesPerActiveTraderLatestDay"]),
            importTotals: parseImportTotals(importObject),
            topFeatures: topFeatures,
            previewFunnel: AdminProductPreviewFunnel(
                starts: AdminUsageAnalyticsParsing.int(funnelObject["starts"]),
                exits: AdminUsageAnalyticsParsing.int(funnelObject["exits"]),
                upgradeTaps: AdminUsageAnalyticsParsing.int(funnelObject["upgradeTaps"]),
                startToUpgradeRate: optionalDouble(funnelObject["startToUpgradeRate"])
            ),
            previewAvailable: previewObject["available"] as? Bool ?? false,
            series: AdminProductAnalyticsSeries(
                signupsPerDay: AdminUsageAnalyticsParsing.parseSeries(growthObject["signupsPerDay"]),
                productActiveUsersPerDay: parseProductActiveSeries(growthObject["productActiveUsersPerDay"]),
                returningUsersPerDay: AdminUsageAnalyticsParsing.parseSeries(retentionObject["returningUsersPerDay"]),
                tradesCreatedPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["tradesCreatedPerDay"]),
                activeTradersPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["activeTradersPerDay"]),
                profileViewsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["profileViewsPerDay"]),
                uniqueProfileViewersPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["uniqueProfileViewersPerDay"]),
                postsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["postsPerDay"]),
                featureEngagementPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["featureEngagementPerDay"]),
                previewStartsPerDay: AdminUsageAnalyticsParsing.parseSeries(previewObject["startsPerDay"]),
                previewExitsPerDay: AdminUsageAnalyticsParsing.parseSeries(previewObject["exitsPerDay"]),
                previewUpgradeTapsPerDay: AdminUsageAnalyticsParsing.parseSeries(previewObject["upgradeTapsPerDay"])
            )
        )
    }

    static func normalizeProductSeries(
        _ bundle: AdminProductAnalyticsBundle
    ) -> AdminProductAnalyticsBundle {
        var copy = bundle
        let d = bundle.seriesDays
        let trackingStart = bundle.meta.productTrackingStartDate
        copy.series = AdminProductAnalyticsSeries(
            signupsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.signupsPerDay, seriesDays: d),
            productActiveUsersPerDay: normalizeProductActiveSeries(
                bundle.series.productActiveUsersPerDay,
                seriesDays: d,
                trackingStart: trackingStart
            ),
            returningUsersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.returningUsersPerDay, seriesDays: d),
            tradesCreatedPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.tradesCreatedPerDay, seriesDays: d),
            activeTradersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.activeTradersPerDay, seriesDays: d),
            profileViewsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.profileViewsPerDay, seriesDays: d),
            uniqueProfileViewersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.uniqueProfileViewersPerDay, seriesDays: d),
            postsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.postsPerDay, seriesDays: d),
            featureEngagementPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.featureEngagementPerDay, seriesDays: d),
            previewStartsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.previewStartsPerDay, seriesDays: d),
            previewExitsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.previewExitsPerDay, seriesDays: d),
            previewUpgradeTapsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.previewUpgradeTapsPerDay, seriesDays: d)
        )
        return copy
    }

    static func productActiveChartPoints(_ points: [AdminProductDailyCount]) -> [AdminUsageDailyCount] {
        points.compactMap { row in
            guard let count = row.count else { return nil }
            return AdminUsageDailyCount(day: row.day, count: count)
        }
    }

    static func parseProductActiveSeries(_ raw: Any?) -> [AdminProductDailyCount] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let day = (row["day"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !day.isEmpty else { return nil }
            let countValue = row["count"]
            if countValue is NSNull { return AdminProductDailyCount(day: day, count: nil) }
            if countValue == nil { return AdminProductDailyCount(day: day, count: nil) }
            return AdminProductDailyCount(day: day, count: AdminUsageAnalyticsParsing.int(countValue))
        }
    }

    static func normalizeProductActiveSeries(
        _ points: [AdminProductDailyCount],
        seriesDays: Int,
        trackingStart: String?
    ) -> [AdminProductDailyCount] {
        guard seriesDays > 0 else { return points }
        let calendar = AdminUsageAnalyticsParsing.utcCalendar
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(seriesDays - 1), to: end) else {
            return points.sorted { $0.day < $1.day }
        }
        var map: [String: Int?] = [:]
        for point in points {
            map[point.day] = point.count
        }
        var output: [AdminProductDailyCount] = []
        var cursor = start
        while cursor <= end {
            let key = AdminUsageAnalyticsParsing.dayKey(calendar, cursor)
            if let trackingStart, key < trackingStart {
                output.append(AdminProductDailyCount(day: key, count: nil))
            } else {
                output.append(AdminProductDailyCount(day: key, count: map[key] ?? 0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }

    private static func parseImportTotals(_ raw: [String: Any]) -> AdminProductImportTotals {
        let legacyManual = AdminUsageAnalyticsParsing.int(raw["manual"])
        let manualEntered = AdminUsageAnalyticsParsing.int(raw["manualEntered"])
        return AdminProductImportTotals(
            manualEntered: manualEntered > 0 ? manualEntered : legacyManual,
            unsetImportSource: AdminUsageAnalyticsParsing.int(raw["unsetImportSource"]),
            csv: AdminUsageAnalyticsParsing.int(raw["csv"]),
            broker: AdminUsageAnalyticsParsing.int(raw["broker"]),
            other: AdminUsageAnalyticsParsing.int(raw["other"])
        )
    }

    private static func parseFeatureRows(_ raw: Any?) -> [AdminProductFeatureUsageRow] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.map { row in
            AdminProductFeatureUsageRow(
                feature: (row["feature"] as? String) ?? "",
                uniqueUsers: AdminUsageAnalyticsParsing.int(row["uniqueUsers"]),
                webUniqueUsers: AdminUsageAnalyticsParsing.int(row["webUniqueUsers"]),
                iosUniqueUsers: AdminUsageAnalyticsParsing.int(row["iosUniqueUsers"]),
                useCount: AdminUsageAnalyticsParsing.int(row["useCount"])
            )
        }
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        if value is NSNull { return nil }
        if value == nil { return nil }
        return AdminUsageAnalyticsParsing.int(value)
    }

    private static func optionalDouble(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let d = value as? Double, d.isFinite { return d }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }
}