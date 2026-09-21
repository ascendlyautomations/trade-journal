import Foundation

nonisolated enum ProfileAnalyticsV2BootstrapApplier {
    struct Applied: Sendable, Equatable {
        var found: Bool
        var publicRevision: Int64?
        var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
    }

    nonisolated static func apply(_ bootstrap: ProfileAnalyticsBootstrapV2) -> Applied {
        guard bootstrap.meta.found else {
            return Applied(found: false, publicRevision: nil, modeResults: [:])
        }
        return Applied(
            found: true,
            publicRevision: bootstrap.publicRevisionInt,
            modeResults: ProfileStatisticsBootstrapModeMapping.mapModes(bootstrap.data.modes)
        )
    }
}
