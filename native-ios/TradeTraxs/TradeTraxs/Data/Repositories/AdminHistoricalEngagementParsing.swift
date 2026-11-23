import Foundation

nonisolated enum AdminHistoricalEngagementParsing {
    static func parseBundle(from data: Data) throws -> AdminHistoricalEngagementBundle {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AdminUsageAnalyticsError.invalidResponse
        }

        let metaObject = root["meta"] as? [String: Any] ?? [:]
        let overviewObject = root["overview"] as? [String: Any] ?? [:]
        let growthObject = root["growth"] as? [String: Any] ?? [:]
        let tradingObject = root["trading"] as? [String: Any] ?? [:]
        let socialObject = root["social"] as? [String: Any] ?? [:]
        let engagementObject = root["engagement"] as? [String: Any] ?? [:]
        let retentionObject = root["retention"] as? [String: Any] ?? [:]
        let importObject = tradingObject["importQuality"] as? [String: Any] ?? [:]

        let notes = (metaObject["notes"] as? [String]) ?? []
        let seriesDays = max(1, AdminUsageAnalyticsParsing.int(root["seriesDays"]))

        return AdminHistoricalEngagementBundle(
            seriesDays: seriesDays,
            meta: AdminHistoricalEngagementMeta(
                notes: notes,
                isContentActivityNotSessions: metaObject["isContentActivityNotSessions"] as? Bool ?? true,
                maxSeriesDays: AdminUsageAnalyticsParsing.clampedInt(
                    AdminUsageAnalyticsParsing.int(metaObject["maxSeriesDays"]),
                    default: 365,
                    min: 1,
                    max: 365
                ),
                periodStart: metaObject["periodStart"] as? String,
                periodEnd: metaObject["periodEnd"] as? String,
                rangeMode: metaObject["rangeMode"] as? String,
                activityFilter: metaObject["activityFilter"] as? String,
                retentionObservationEnd: metaObject["retentionObservationEnd"] as? String
            ),
            overview: AdminHistoricalEngagementOverview(
                engagedDau: AdminUsageAnalyticsParsing.int(overviewObject["engagedDau"]),
                engagedWau: AdminUsageAnalyticsParsing.int(overviewObject["engagedWau"]),
                engagedMau: AdminUsageAnalyticsParsing.int(overviewObject["engagedMau"]),
                activeTradersDau: AdminUsageAnalyticsParsing.int(overviewObject["activeTradersDau"]),
                activeCreatorsDau: AdminUsageAnalyticsParsing.int(overviewObject["activeCreatorsDau"]),
                activeMessengersDau: AdminUsageAnalyticsParsing.int(overviewObject["activeMessengersDau"]),
                newSignupsInPeriod: AdminUsageAnalyticsParsing.int(overviewObject["newSignupsInPeriod"]),
                accountsCreatedInPeriod: AdminUsageAnalyticsParsing.int(overviewObject["accountsCreatedInPeriod"])
            ),
            retentionD1Rate: optionalDouble(retentionObject["d1Rate"]),
            retentionD7Rate: optionalDouble(retentionObject["d7Rate"]),
            retentionD30Rate: optionalDouble(retentionObject["d30Rate"]),
            cohortSignupsTotal: AdminUsageAnalyticsParsing.int(retentionObject["cohortSignupsTotal"]),
            retentionInsufficientData: retentionObject["insufficientData"] as? Bool ?? false,
            retentionD1MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d1MatureCohortSize"]),
            retentionD7MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d7MatureCohortSize"]),
            retentionD30MatureCohortSize: AdminUsageAnalyticsParsing.int(retentionObject["d30MatureCohortSize"]),
            retentionDefinition: retentionObject["definition"] as? String ?? "",
            trading: AdminHistoricalTradingSeries(
                tradesLoggedPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["tradesLoggedPerDay"]),
                organicTradesLoggedPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["organicTradesLoggedPerDay"]),
                bulkImportTradesPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["bulkImportTradesPerDay"]),
                tradesByExecutionDatePerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["tradesByExecutionDatePerDay"]),
                activeTradersPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["activeTradersPerDay"]),
                returningTradersPerDay: AdminUsageAnalyticsParsing.parseSeries(tradingObject["returningTradersPerDay"]),
                importQuality: parseImportQuality(importObject)
            ),
            social: AdminHistoricalSocialSeries(
                postsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["postsPerDay"]),
                profilePostsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["profilePostsPerDay"]),
                reelsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["reelsPerDay"]),
                commentsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["commentsPerDay"]),
                likesPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["likesPerDay"]),
                followsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["followsPerDay"]),
                messagesPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["messagesPerDay"]),
                activeCreatorsPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["activeCreatorsPerDay"]),
                activeMessengersPerDay: AdminUsageAnalyticsParsing.parseSeries(socialObject["activeMessengersPerDay"])
            ),
            series: AdminHistoricalEngagementSeries(
                signupsPerDay: AdminUsageAnalyticsParsing.parseSeries(growthObject["signupsPerDay"]),
                accountsCreatedPerDay: AdminUsageAnalyticsParsing.parseSeries(growthObject["accountsCreatedPerDay"]),
                engagedUsersPerDay: AdminUsageAnalyticsParsing.parseSeries(engagementObject["engagedUsersPerDay"]),
                returningEngagedUsersPerDay: AdminUsageAnalyticsParsing.parseSeries(engagementObject["returningEngagedUsersPerDay"]),
                returningCreatorsPerDay: AdminUsageAnalyticsParsing.parseSeries(engagementObject["returningCreatorsPerDay"])
            )
        )
    }

    static func normalizeSeries(_ bundle: AdminHistoricalEngagementBundle) -> AdminHistoricalEngagementBundle {
        var copy = bundle
        let d = bundle.seriesDays
        copy.trading = AdminHistoricalTradingSeries(
            tradesLoggedPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.tradesLoggedPerDay, seriesDays: d),
            organicTradesLoggedPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.organicTradesLoggedPerDay, seriesDays: d),
            bulkImportTradesPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.bulkImportTradesPerDay, seriesDays: d),
            tradesByExecutionDatePerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.tradesByExecutionDatePerDay, seriesDays: d),
            activeTradersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.activeTradersPerDay, seriesDays: d),
            returningTradersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.trading.returningTradersPerDay, seriesDays: d),
            importQuality: bundle.trading.importQuality
        )
        copy.social = AdminHistoricalSocialSeries(
            postsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.postsPerDay, seriesDays: d),
            profilePostsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.profilePostsPerDay, seriesDays: d),
            reelsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.reelsPerDay, seriesDays: d),
            commentsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.commentsPerDay, seriesDays: d),
            likesPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.likesPerDay, seriesDays: d),
            followsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.followsPerDay, seriesDays: d),
            messagesPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.messagesPerDay, seriesDays: d),
            activeCreatorsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.activeCreatorsPerDay, seriesDays: d),
            activeMessengersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.social.activeMessengersPerDay, seriesDays: d)
        )
        copy.series = AdminHistoricalEngagementSeries(
            signupsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.signupsPerDay, seriesDays: d),
            accountsCreatedPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.accountsCreatedPerDay, seriesDays: d),
            engagedUsersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.engagedUsersPerDay, seriesDays: d),
            returningEngagedUsersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.returningEngagedUsersPerDay, seriesDays: d),
            returningCreatorsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.returningCreatorsPerDay, seriesDays: d)
        )
        return copy
    }

    private static func parseImportQuality(_ object: [String: Any]) -> AdminHistoricalImportQuality {
        AdminHistoricalImportQuality(
            manualEntered: AdminUsageAnalyticsParsing.int(object["manualEntered"]),
            unsetImportSource: AdminUsageAnalyticsParsing.int(object["unsetImportSource"]),
            csv: AdminUsageAnalyticsParsing.int(object["csv"]),
            broker: AdminUsageAnalyticsParsing.int(object["broker"]),
            other: AdminUsageAnalyticsParsing.int(object["other"]),
            bulkInitialImportRows: AdminUsageAnalyticsParsing.int(object["bulkInitialImportRows"]),
            organicTradesLogged: AdminUsageAnalyticsParsing.int(object["organicTradesLogged"]),
            tradeDateBeforeCreatedDayRows: AdminUsageAnalyticsParsing.int(object["tradeDateBeforeCreatedDayRows"]),
            nullTradeDateRows: AdminUsageAnalyticsParsing.int(object["nullTradeDateRows"])
        )
    }

    private static func optionalDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }
}