import Foundation

#if DEBUG
enum DashboardAnalyticsV3Probe {
    static func log(
        source: String,
        reason: String?,
        range: String?,
        account: String?,
        mode: String?,
        revision: Int64?,
        payloadBytes: Int?,
        summaryCount: Int?,
        dailyRows: Int,
        equityPoints: Int?,
        elapsedMs: Int?
    ) {
        var parts = ["[DashboardV3]", "source=\(source)"]
        if let reason { parts.append("reason=\(reason)") }
        if let range { parts.append("range=\(range)") }
        if let account { parts.append("account=\(account)") }
        if let mode { parts.append("mode=\(mode)") }
        if let revision { parts.append("revision=\(revision)") }
        if let payloadBytes { parts.append("payloadBytes=\(payloadBytes)") }
        if let summaryCount { parts.append("summaryCount=\(summaryCount)") }
        parts.append("dailyRows=\(dailyRows)")
        if let equityPoints { parts.append("equityPoints=\(equityPoints)") }
        if let elapsedMs { parts.append("elapsedMs=\(elapsedMs)") }
        print(parts.joined(separator: " "))
    }
}
#else
enum DashboardAnalyticsV3Probe {
    static func log(
        source: String,
        reason: String?,
        range: String?,
        account: String?,
        mode: String?,
        revision: Int64?,
        payloadBytes: Int?,
        summaryCount: Int?,
        dailyRows: Int,
        equityPoints: Int?,
        elapsedMs: Int?
    ) {}
}
#endif
