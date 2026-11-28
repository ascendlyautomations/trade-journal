import Foundation

nonisolated struct ProfileInsightsRepository: Sendable {
    private let rpc: any RPCClient

    init(rpc: any RPCClient) {
        self.rpc = rpc
    }

    func loadInsights(days: Int) async throws -> ProfileInsightsBootstrapV1 {
        try await loadInsights(query: .preset(days: days))
    }

    func loadInsights(query: ProfileInsightsQuery) async throws -> ProfileInsightsBootstrapV1 {
        struct Args: Encodable {
            var p_days: Int?
            var p_start: String?
            var p_end: String?
        }

        let args: Args
        switch query {
        case .preset(let days):
            args = Args(p_days: days, p_start: nil, p_end: nil)
        case .custom(let startYMD, let endYMD):
            args = Args(p_days: nil, p_start: startYMD, p_end: endYMD)
        }

        let rpcName = BackendV2Versioning.RPCName.profileInsightsBootstrap.rawValue
        let body = try JSONEncoder().encode(args)
        #if DEBUG
        ProfileInsightsDebugLog.logRPCRequest(query: query, jsonBody: body)
        #endif
        let data: Data
        do {
            data = try await rpc.call(functionName: rpcName, jsonBody: body)
        } catch {
            #if DEBUG
            ProfileInsightsDebugLog.logTransportFailure(error)
            #endif
            throw error
        }
        #if DEBUG
        ProfileInsightsDebugLog.logRPCResponseReceived(byteCount: data.count)
        ProfileInsightsDebugLog.logContractProbe(payload: data)
        #endif
        do {
            return try JSONDecoder().decode(ProfileInsightsBootstrapV1.self, from: data)
        } catch {
            #if DEBUG
            ProfileInsightsDebugLog.logDecodeFailure(error, payloadBytes: data.count)
            #endif
            throw error
        }
    }
}