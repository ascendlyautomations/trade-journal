import Foundation

nonisolated struct ViewerSyncStateV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataSection

    struct DataSection: Codable, Sendable, Equatable {
        var trades: TradesDomain
        var accounts: AccountsDomain
        var profile: ProfileDomain
    }

    struct TradesDomain: Codable, Sendable, Equatable {
        var count: Int
        var max_created_at: String?
        var checksum: Int64
    }

    struct AccountsDomain: Codable, Sendable, Equatable {
        var count: Int
        var max_created_at: String?
        var checksum: Int64
    }

    struct ProfileDomain: Codable, Sendable, Equatable {
        var checksum: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated enum ViewerSyncDomain: String, Codable, Sendable, CaseIterable {
    case trades
    case accounts
    case profile
}

nonisolated struct ViewerSyncStateFingerprints: Codable, Sendable, Equatable {
    var viewerID: String
    var trades: ViewerSyncStateV1.TradesDomain
    var accounts: ViewerSyncStateV1.AccountsDomain
    var profile: ViewerSyncStateV1.ProfileDomain
    var lastServerTime: String?
    var lastVerifiedAt: Date

    init(viewerID: String, response: ViewerSyncStateV1, verifiedAt: Date = Date()) {
        self.viewerID = viewerID
        trades = response.data.trades
        accounts = response.data.accounts
        profile = response.data.profile
        lastServerTime = response.meta.server_time
        lastVerifiedAt = verifiedAt
    }

    func changedDomains(comparedTo server: ViewerSyncStateFingerprints) -> [ViewerSyncDomain] {
        var changed: [ViewerSyncDomain] = []
        if trades != server.trades { changed.append(.trades) }
        if accounts != server.accounts { changed.append(.accounts) }
        if profile != server.profile { changed.append(.profile) }
        return changed
    }

    func matches(_ server: ViewerSyncStateFingerprints) -> Bool {
        changedDomains(comparedTo: server).isEmpty
    }
}

extension ViewerSyncStateV1 {
    var fingerprints: ViewerSyncStateFingerprints {
        ViewerSyncStateFingerprints(
            viewerID: meta.viewer_id ?? "",
            response: self
        )
    }
}
