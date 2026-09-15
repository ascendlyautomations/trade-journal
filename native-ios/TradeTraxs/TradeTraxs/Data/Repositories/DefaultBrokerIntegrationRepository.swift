import Foundation

nonisolated struct DefaultBrokerIntegrationRepository: BrokerIntegrationRepository {
    private static let nativeOAuthClientHeader = "x-tradetraxs-broker-oauth-client"
    private static let nativeOAuthClientValue = "native"

    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func listTradovateConnections() async throws -> TradovateConnectionsResponse {
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/tradovate/connections",
            method: .get,
            requiresAuthentication: true
        )
        BrokerIntegrationDebugLog.connectionsResponse(status: response.statusCode, bytes: response.data.count)
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Could not load Tradovate connections.")
        }
        let decoded: TradovateConnectionsResponse
        do {
            decoded = try transport.decoder.decode(TradovateConnectionsResponse.self, from: response)
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: "connections", detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
        BrokerIntegrationDebugLog.connectionsDecoded(count: decoded.connections.count)
        let active = decoded.connections.filter(\.isActiveForBrokerUI).count
        BrokerIntegrationDebugLog.connectionsActive(count: active)
        for connection in decoded.connections {
            let idPresent = !connection.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            BrokerIntegrationDebugLog.connectionRow(idPresent: idPresent, status: connection.status.rawValue)
        }
        return decoded
    }

    func beginTradovateNativeOAuth(reconnectConnectionId: String?) async throws -> URL {
        struct Body: Encodable {
            var client: String = "native"
            var reconnectConnectionId: String?
        }
        let payload = Body(reconnectConnectionId: reconnectConnectionId)
        let body = try transport.encodeJSON(payload)
        BrokerOAuthDebugLog.authorizeRequest(client: "native", bodyIncluded: !body.isEmpty)
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/tradovate/authorize",
            method: .post,
            headers: [Self.nativeOAuthClientHeader: Self.nativeOAuthClientValue],
            body: body,
            requiresAuthentication: true
        )
        let decoded: TradovateAuthorizeNativeResponse
        if (200 ... 299).contains(response.statusCode) {
            do {
                decoded = try transport.decoder.decode(TradovateAuthorizeNativeResponse.self, from: response)
            } catch {
                BrokerIntegrationDebugLog.decodeFailure(context: "authorize", detail: String(describing: error))
                throw AppError.unknown(message: brokerDecodeUserMessage)
            }
        } else {
            throw brokerError(from: response, fallback: "Could not start Tradovate connection.")
        }
        let urlString = decoded.resolvedAuthorizeURLString
        BrokerOAuthDebugLog.authorizeResponse(
            status: response.statusCode,
            ok: decoded.ok,
            hasAuthorizeURL: urlString != nil
        )
        guard decoded.ok, let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            if decoded.ok, urlString == nil {
                throw AppError.unknown(
                    message: "Tradovate sign-in URL was missing. Confirm the app and server support native broker connect, then try again."
                )
            }
            throw brokerError(from: response, fallback: decoded.error ?? "Could not start Tradovate connection.")
        }
        return url
    }

    func listTradovateAccounts(connectionId: String, forceRefresh: Bool) async throws -> TradovateConnectionAccountsResponse {
        let trimmedId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        BrokerIntegrationDebugLog.accountsRequest(connectionIdPresent: !trimmedId.isEmpty)
        var query: [URLQueryItem] = []
        if forceRefresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/tradovate/connections/\(trimmedId)/accounts",
            method: .get,
            queryItems: query,
            requiresAuthentication: true
        )
        BrokerIntegrationDebugLog.accountsResponse(status: response.statusCode, bytes: response.data.count)
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Could not load broker accounts for this connection.")
        }
        do {
            let decoded = try transport.decoder.decode(TradovateConnectionAccountsResponse.self, from: response)
            BrokerIntegrationDebugLog.accountsDecoded(count: decoded.accounts.count)
            return decoded
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: "accounts", detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
    }

    func linkTradovateAccount(
        connectionId: String,
        brokerIntegrationAccountId: String,
        tradetraxsAccountId: String
    ) async throws -> BrokerLinkAccountsResponse {
        struct Body: Encodable {
            var action: String = "link"
            var brokerIntegrationAccountId: String
            var tradetraxsAccountId: String
        }
        let body = try transport.encodeJSON(
            Body(
                brokerIntegrationAccountId: brokerIntegrationAccountId,
                tradetraxsAccountId: tradetraxsAccountId
            )
        )
        return try await post("/api/integrations/tradovate/connections/\(connectionId)/accounts/link", body: body)
    }

    func createAndLinkTradovateAccount(
        connectionId: String,
        brokerIntegrationAccountId: String,
        draft: TradingAccountDraft
    ) async throws -> BrokerLinkAccountsResponse {
        struct CreatePayload: Encodable {
            var name: String
            var size: String
            var accountNumber: String
            var category: String
            var mode: String
            var rules: String? = nil
        }
        struct Body: Encodable {
            var action: String = "create"
            var brokerIntegrationAccountId: String
            var createAccount: CreatePayload
        }
        let payload = CreatePayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            size: draft.sizeDigits.trimmingCharacters(in: .whitespacesAndNewlines),
            accountNumber: draft.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            category: BrokerIntegrationAccountDraftEncoding.webCategory(draft.category),
            mode: BrokerIntegrationAccountDraftEncoding.webMode(draft.mode, category: draft.category)
        )
        let body = try transport.encodeJSON(
            Body(brokerIntegrationAccountId: brokerIntegrationAccountId, createAccount: payload)
        )
        return try await post("/api/integrations/tradovate/connections/\(connectionId)/accounts/link", body: body)
    }

    func syncTradovateAccount(connectionId: String, mappingId: String) async throws -> TradovateAccountSyncResponse {
        try await post(
            "/api/integrations/tradovate/connections/\(connectionId)/accounts/\(mappingId)/sync",
            body: Data()
        )
    }

    func runBrokerImport(mappingIds: [String]) async throws -> BrokerManualImportResponse {
        struct Body: Encodable { var mappingIds: [String] }
        let body = try transport.encodeJSON(Body(mappingIds: mappingIds))
        return try await post("/api/integrations/broker/import/run", body: body)
    }

    func importEligibility() async throws -> BrokerImportEligibilityResponse {
        try await get("/api/integrations/broker/import/eligibility")
    }

    func disconnectTradovate(connectionId: String) async throws {
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/tradovate/connections/\(connectionId)/disconnect",
            method: .post,
            body: Data(),
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Could not disconnect Tradovate.")
        }
    }

    // MARK: - HTTP helpers

    private var brokerDecodeUserMessage: String {
        "Could not read broker response. Check for an app update or try again later."
    }

    private func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .get,
            queryItems: queryItems,
            requiresAuthentication: true
        )
        return try decode(T.self, from: response, context: path)
    }

    private func post<T: Decodable>(_ path: String, body: Data) async throws -> T {
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .post,
            body: body.isEmpty ? nil : body,
            requiresAuthentication: true
        )
        return try decode(T.self, from: response, context: path)
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse, context: String) throws -> T {
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Broker request failed (\(response.statusCode)).")
        }
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: context, detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
    }

    private func brokerError(from response: HTTPResponse, fallback: String) -> AppError {
        struct ErrorBody: Decodable { var error: String? }
        if let body = try? transport.decoder.decode(ErrorBody.self, from: response),
           let message = body.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty
        {
            return .unknown(message: message)
        }
        return .unknown(message: fallback)
    }
}

nonisolated enum BrokerIntegrationAccountDraftEncoding {
    static func webCategory(_ category: TradingAccountCategory) -> String {
        switch category {
        case .personal: return "Personal"
        case .broker: return "Broker"
        case .propFirm: return "Prop Firm"
        case .backtest: return "Backtest"
        }
    }

    static func webMode(_ mode: TradingAccountMode, category: TradingAccountCategory) -> String {
        switch category {
        case .propFirm:
            return mode == .funded ? "Funded" : "Eval"
        case .backtest:
            return "Backtest"
        case .personal, .broker:
            return mode == .sim ? "Sim" : "Live"
        }
    }

    static func draft(
        externalAccountId: String,
        externalAccountName: String?,
        metadata: [String: JSONBrokerValue]
    ) -> TradingAccountDraft {
        let trimmedName = externalAccountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let providerName = trimmedName.isEmpty ? externalAccountId : trimmedName
        let evaluationSize = metadata["evaluationSize"]?.doubleValue
        let sizeDigits =
            evaluationSize != nil ? String(Int(evaluationSize!.rounded())) : ""
        let accountNumber = trimmedName.isEmpty ? externalAccountId : trimmedName
        return TradingAccountDraft(
            name: providerName,
            sizeDigits: sizeDigits,
            accountNumber: accountNumber,
            category: .personal,
            mode: .live,
            note: "",
            propFirmRules: nil
        )
    }
}
