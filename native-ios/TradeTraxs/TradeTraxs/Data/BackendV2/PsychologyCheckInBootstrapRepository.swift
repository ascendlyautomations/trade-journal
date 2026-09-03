import Foundation

nonisolated struct PsychologyCheckInBootstrapV1: Codable, Sendable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable {
        var check_ins: [TraderDailyCheckInDTO.Row]
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated enum PsychologyCheckInBootstrapLoader {
    static func load(
        rpc: any RPCClient,
        accountID: TradingAccountID?
    ) async throws -> [TraderDailyCheckIn] {
        let client = BackendV2RPCClient(transport: rpc)
        let args = PsychologyCheckInRpcArguments(
            p_account_id: accountID?.rawValue
        )
        let body = try JSONEncoder().encode(args)
        let bootstrap = try await client.call(
            .psychologyCheckInWindow,
            argumentsJSON: body,
            as: PsychologyCheckInBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.dashboard.dottedName
            )
        )
        try bootstrap.validateContractVersion()
        return try bootstrap.data.check_ins.map { try TraderDailyCheckInMapper.map($0) }
    }
}

private nonisolated struct PsychologyCheckInRpcArguments: Encodable, Sendable {
    var p_account_id: String?
}
