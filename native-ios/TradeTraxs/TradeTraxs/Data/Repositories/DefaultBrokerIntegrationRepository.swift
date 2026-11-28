import Foundation

nonisolated struct DefaultBrokerIntegrationRepository: BrokerIntegrationRepository {
    private static let nativeOAuthClientHeader = "x-tradetraxs-broker-oauth-client"
    private static let nativeOAuthClientValue = "native"

    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func listTradovateConnections() async throws -> TradovateConnectionsResponse {
        let started = ContinuousClock.now
        TradovateConnectionDiagnostics.requestStarted()
        do {
            let response = try await transport.send(
                host: .bff,
                path: "/api/integrations/tradovate/connections",
                method: .get,
                requiresAuthentication: true
            )
            let durationMs = Self.durationMilliseconds(since: started)
            BrokerIntegrationDebugLog.connectionsResponse(status: response.statusCode, bytes: response.data.count)
            guard (200 ... 299).contains(response.statusCode) else {
                TradovateConnectionDiagnostics.requestFailed(
                    category: "http\(response.statusCode)",
                    durationMs: durationMs
                )
                throw brokerError(from: response, fallback: "Could not load Tradovate connections.")
            }
            let decoded: TradovateConnectionsResponse
            do {
                decoded = try transport.decoder.decode(TradovateConnectionsResponse.self, from: response)
            } catch {
                BrokerIntegrationDebugLog.decodeFailure(context: "connections", detail: String(describing: error))
                TradovateConnectionDiagnostics.requestFailed(category: "decode", durationMs: durationMs)
                throw AppError.unknown(message: brokerDecodeUserMessage)
            }
            BrokerIntegrationDebugLog.connectionsDecoded(count: decoded.connections.count)
            let active = decoded.connections.filter(\.isActiveForBrokerUI).count
            BrokerIntegrationDebugLog.connectionsActive(count: active)
            TradovateConnectionDiagnostics.requestSucceeded(
                httpStatus: response.statusCode,
                connectionCount: decoded.connections.count,
                activeConnectionCount: active,
                durationMs: durationMs
            )
            for connection in decoded.connections {
                let idPresent = !connection.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                BrokerIntegrationDebugLog.connectionRow(
                    idPresent: idPresent,
                    status: connection.status.rawValue,
                    apiEnvironment: connection.apiEnvironment
                )
            }
            return decoded
        } catch {
            TradovateConnectionDiagnostics.requestFailed(
                category: TradovateConnectionDiagnostics.safeFailureCategory(for: error),
                durationMs: Self.durationMilliseconds(since: started)
            )
            throw error
        }
    }

    private static func durationMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    func beginTradovateNativeOAuth(
        reconnectConnectionId: String?,
        apiEnvironment: String?
    ) async throws -> URL {
        struct Body: Encodable {
            var client: String = "native"
            var reconnectConnectionId: String?
            var apiEnvironment: String?
        }
        let payload = Body(
            reconnectConnectionId: reconnectConnectionId,
            apiEnvironment: apiEnvironment
        )
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
        let payloadProbe = Self.probeTradovateAccountsPayload(response.data)
        do {
            let decoded = try transport.decoder.decode(TradovateConnectionAccountsResponse.self, from: response)
            BrokerIntegrationDebugLog.accountsDecoded(count: decoded.accounts.count)
            BrokerIntegrationDebugLog.accountsDiscoverySummary(
                state: decoded.state,
                connectionStatus: decoded.connectionStatus,
                forceRefresh: forceRefresh,
                rawAccountsCount: payloadProbe.rawAccountsCount,
                accountsKeyPresent: payloadProbe.accountsKeyPresent,
                discoveryOk: decoded.discovery?.ok ?? payloadProbe.discoveryOk,
                discoveryReason: decoded.discovery?.reason ?? payloadProbe.discoveryReason,
                discoveryAccountCount: decoded.discovery?.accountCount ?? payloadProbe.discoveryAccountCount
            )
            return decoded
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: "accounts", detail: String(describing: error))
            if let rawCount = payloadProbe.rawAccountsCount, rawCount > 0 {
                BrokerIntegrationDebugLog.accountsItemDecodeProbe(
                    expectedRawCount: rawCount,
                    decodedCount: 0
                )
            }
            BrokerIntegrationDebugLog.accountsDiscoverySummary(
                state: payloadProbe.state ?? "decode_failed",
                connectionStatus: payloadProbe.connectionStatus,
                forceRefresh: forceRefresh,
                rawAccountsCount: payloadProbe.rawAccountsCount,
                accountsKeyPresent: payloadProbe.accountsKeyPresent,
                discoveryOk: payloadProbe.discoveryOk,
                discoveryReason: payloadProbe.discoveryReason,
                discoveryAccountCount: payloadProbe.discoveryAccountCount
            )
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
    }

    private struct TradovateAccountsPayloadProbe: Sendable {
        var state: String?
        var connectionStatus: String?
        var accountsKeyPresent: Bool
        var rawAccountsCount: Int?
        var discoveryOk: Bool?
        var discoveryReason: String?
        var discoveryAccountCount: Int?
    }

    private static func probeTradovateAccountsPayload(_ data: Data) -> TradovateAccountsPayloadProbe {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return TradovateAccountsPayloadProbe(
                state: nil,
                connectionStatus: nil,
                accountsKeyPresent: false,
                rawAccountsCount: nil,
                discoveryOk: nil,
                discoveryReason: nil,
                discoveryAccountCount: nil
            )
        }
        let state = object["state"] as? String
        let connectionStatus =
            (object["connectionStatus"] as? String) ?? (object["connection_status"] as? String)
        let accountsValue = object["accounts"]
        let accountsKeyPresent = object.keys.contains("accounts")
        let rawAccountsCount: Int? = {
            if let list = accountsValue as? [Any] { return list.count }
            if accountsValue == nil || accountsValue is NSNull { return 0 }
            return nil
        }()
        var discoveryOk: Bool?
        var discoveryReason: String?
        var discoveryAccountCount: Int?
        if let discovery = object["discovery"] as? [String: Any] {
            if let ok = discovery["ok"] as? Bool {
                discoveryOk = ok
            }
            discoveryReason = discovery["reason"] as? String
            discoveryAccountCount = discovery["accountCount"] as? Int
        }
        return TradovateAccountsPayloadProbe(
            state: state,
            connectionStatus: connectionStatus,
            accountsKeyPresent: accountsKeyPresent,
            rawAccountsCount: rawAccountsCount,
            discoveryOk: discoveryOk,
            discoveryReason: discoveryReason,
            discoveryAccountCount: discoveryAccountCount
        )
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
            var purchaseCost: String
            var purchaseDate: String
        }
        struct Body: Encodable {
            var action: String = "create"
            var brokerIntegrationAccountId: String
            var createAccount: CreatePayload
        }
        let payload = CreatePayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            size: NumericInputFieldSupport.plainNumericString(from: draft.sizeDigits),
            accountNumber: draft.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            category: BrokerIntegrationAccountDraftEncoding.webCategory(draft.category),
            mode: BrokerIntegrationAccountDraftEncoding.webMode(draft.mode, category: draft.category),
            purchaseCost: NumericInputFieldSupport.plainNumericString(from: draft.purchaseCostDigits),
            purchaseDate: draft.purchaseDate.map { PropFirmExpenseMoney.dayString(from: $0) } ?? ""
        )
        let body = try transport.encodeJSON(
            Body(brokerIntegrationAccountId: brokerIntegrationAccountId, createAccount: payload)
        )
        return try await post("/api/integrations/tradovate/connections/\(connectionId)/accounts/link", body: body)
    }

    func syncTradovateAccount(
        connectionId: String,
        mappingId: String,
        mode: TradovateSyncRequestMode
    ) async throws -> TradovateAccountSyncResponse {
        struct Body: Encodable { var mode: String }
        let path = "/api/integrations/tradovate/connections/\(connectionId)/accounts/\(mappingId)/sync"
        let body = try transport.encodeJSON(Body(mode: mode.rawValue))
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .post,
            body: body,
            requiresAuthentication: true
        )
        return try decodeBrokerAccountSync(from: response, context: path)
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

    func setTradovatePendingLink(
        connectionId: String,
        tradetraxsAccountId: String
    ) async throws -> BrokerConnectionPendingLinkPreference {
        struct Body: Encodable {
            var action: String = "link"
            var tradetraxsAccountId: String
        }
        let body = try transport.encodeJSON(
            Body(tradetraxsAccountId: tradetraxsAccountId)
        )
        return try await postPendingLink(connectionId: connectionId, body: body)
    }

    func createTradovatePendingLink(
        connectionId: String,
        draft: TradingAccountDraft
    ) async throws -> BrokerConnectionPendingLinkPreference {
        struct CreatePayload: Encodable {
            var name: String
            var size: String
            var accountNumber: String
            var category: String
            var mode: String
            var rules: String? = nil
            var purchaseCost: String
            var purchaseDate: String
        }
        struct Body: Encodable {
            var action: String = "create"
            var createAccount: CreatePayload
        }
        let payload = CreatePayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            size: NumericInputFieldSupport.plainNumericString(from: draft.sizeDigits),
            accountNumber: draft.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            category: BrokerIntegrationAccountDraftEncoding.webCategory(draft.category),
            mode: BrokerIntegrationAccountDraftEncoding.webMode(draft.mode, category: draft.category),
            purchaseCost: NumericInputFieldSupport.plainNumericString(from: draft.purchaseCostDigits),
            purchaseDate: draft.purchaseDate.map { PropFirmExpenseMoney.dayString(from: $0) } ?? ""
        )
        let body = try transport.encodeJSON(Body(createAccount: payload))
        return try await postPendingLink(connectionId: connectionId, body: body)
    }

    func clearTradovatePendingLink(connectionId: String) async throws {
        let clearBody = try transport.encodeJSON(PendingTradetraxsLinkClearBody())
        do {
            _ = try await postPendingLinkResponse(connectionId: connectionId, innerBody: clearBody)
            return
        } catch {
            // Fall through for older BFF builds that only exposed DELETE on the dedicated path.
        }

        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/tradovate/connections/\(connectionId)/pending-link",
            method: .delete,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Could not clear pending link.")
        }
    }

    private struct PendingTradetraxsLinkClearBody: Encodable {
        var action: String = "clear"
    }

    private func postPendingLink(
        connectionId: String,
        body: Data
    ) async throws -> BrokerConnectionPendingLinkPreference {
        let response = try await postPendingLinkResponse(connectionId: connectionId, innerBody: body)
        do {
            return try transport.decoder.decode(
                TradovatePendingLinkMutationResponse.self,
                from: response
            ).pendingLink
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: "pending-link", detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
    }

    private func postPendingLinkResponse(
        connectionId: String,
        innerBody: Data
    ) async throws -> HTTPResponse {
        let refreshPath = "/api/integrations/tradovate/connections/\(connectionId)/accounts/refresh"
        let dedicatedPath = "/api/integrations/tradovate/connections/\(connectionId)/pending-link"
        let refreshBody = try wrapPendingTradetraxsLinkEnvelope(innerBody)

        var failures: [AppError] = []

        for attempt in [
            (refreshPath, refreshBody),
            (dedicatedPath, innerBody),
        ] {
            let response: HTTPResponse
            do {
                response = try await transport.send(
                    host: .bff,
                    path: attempt.0,
                    method: .post,
                    body: attempt.1,
                    requiresAuthentication: true
                )
            } catch {
                failures.append(.unknown(message: UserFacingError.message(for: error)))
                continue
            }

            if response.statusCode == 404 {
                failures.append(.unknown(message: "Pending link API is unavailable (HTTP 404)."))
                continue
            }

            guard (200 ... 299).contains(response.statusCode) else {
                failures.append(brokerError(from: response, fallback: "Could not save pending link."))
                continue
            }

            guard Self.responseLooksLikeJSONObject(response.data) else {
                BrokerIntegrationDebugLog.decodeFailure(
                    context: "pending-link",
                    detail: "non_json body status=\(response.statusCode) path=\(attempt.0)"
                )
                failures.append(.unknown(message: brokerDecodeUserMessage))
                continue
            }

            guard Self.responseLooksLikePendingLinkMutation(response.data) else {
                BrokerIntegrationDebugLog.decodeFailure(
                    context: "pending-link",
                    detail: "missing pendingLink envelope path=\(attempt.0)"
                )
                failures.append(.unknown(message: brokerDecodeUserMessage))
                continue
            }

            return response
        }

        throw failures.last ?? AppError.unknown(message: "Could not save pending link.")
    }

    private func wrapPendingTradetraxsLinkEnvelope(_ innerBody: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: innerBody) as? [String: Any] else {
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
        return try JSONSerialization.data(withJSONObject: ["pendingTradetraxsLink": object])
    }

    private static func responseLooksLikeJSONObject(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            object is [String: Any]
        else {
            return false
        }
        return true
    }

    private static func responseLooksLikePendingLinkMutation(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if object["pendingLink"] != nil || object["pending_link"] != nil {
            return true
        }
        return (object["ok"] as? Bool) == true
    }

    // MARK: - Rithmic

    func fetchRithmicConnectCapabilities() async throws -> RithmicConnectCapabilitiesResponse {
        let capabilities: RithmicConnectCapabilitiesResponse = try await get("/api/integrations/rithmic/connect")
        BrokerIntegrationDebugLog.rithmicConnectCapabilities(
            apiEnvironment: capabilities.apiEnvironment,
            userConnectEnabled: capabilities.userConnectEnabled,
            showConnectUi: capabilities.showConnectUi
        )
        return capabilities
    }

    func listRithmicConnections() async throws -> TradovateConnectionsResponse {
        try await get("/api/integrations/rithmic/connections")
    }

    func connectRithmic(
        username: String,
        password: String,
        systemName: String?,
        reconnectConnectionId: String?
    ) async throws -> RithmicConnectOutcome {
        struct Body: Encodable {
            var username: String
            var password: String
            var systemName: String?
            var reconnectConnectionId: String?
        }
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try transport.encodeJSON(
            Body(
                username: trimmedUser,
                password: password,
                systemName: Self.optionalTrimmed(systemName),
                reconnectConnectionId: Self.optionalTrimmed(reconnectConnectionId)
            )
        )
        let requestedSystem = Self.optionalTrimmed(systemName)
        let response: HTTPResponse
        do {
            response = try await transport.send(
                host: .bff,
                path: "/api/integrations/rithmic/connect",
                method: .post,
                body: body,
                requiresAuthentication: true,
                acceptsNonSuccessStatusCodes: true
            )
        } catch {
            BrokerIntegrationDebugLog.rithmicConnectTransportFailure(detail: String(describing: error))
            throw error
        }
        let decoded: RithmicConnectResponse
        do {
            decoded = try transport.decoder.decode(RithmicConnectResponse.self, from: response)
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: "rithmic.connect", detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
        BrokerIntegrationDebugLog.rithmicConnectResponse(
            httpStatus: response.statusCode,
            ok: decoded.ok,
            code: decoded.code,
            requestedSystemName: requestedSystem,
            responseSystemName: decoded.systemName,
            loginRpCode: decoded.loginRpCode,
            systemNamesCount: decoded.systemNames?.count
        )
        if decoded.code == "system_selection_required",
           let names = decoded.systemNames,
           !names.isEmpty
        {
            return .systemSelectionRequired(
                systemNames: names,
                message: decoded.userMessage ?? "Select a Rithmic system."
            )
        }
        guard (200 ... 299).contains(response.statusCode), decoded.ok,
              let connectionId = Self.optionalTrimmed(decoded.connectionId),
              let system = Self.optionalTrimmed(decoded.systemName)
        else {
            let message = Self.optionalTrimmed(decoded.userMessage)
                ?? "Could not connect Rithmic."
            throw AppError.unknown(message: message)
        }
        return .connected(
            connectionId: connectionId,
            systemName: system,
            accountCount: decoded.accountCount ?? 0
        )
    }

    func listRithmicAccounts(connectionId: String) async throws -> TradovateConnectionAccountsResponse {
        let trimmedId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await get("/api/integrations/rithmic/connections/\(trimmedId)/accounts")
    }

    func linkRithmicAccount(
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
        return try await post("/api/integrations/rithmic/connections/\(connectionId)/accounts/link", body: body)
    }

    func createAndLinkRithmicAccount(
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
            var purchaseCost: String
            var purchaseDate: String
        }
        struct Body: Encodable {
            var action: String = "create"
            var brokerIntegrationAccountId: String
            var createAccount: CreatePayload
        }
        let payload = CreatePayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            size: NumericInputFieldSupport.plainNumericString(from: draft.sizeDigits),
            accountNumber: draft.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            category: BrokerIntegrationAccountDraftEncoding.webCategory(draft.category),
            mode: BrokerIntegrationAccountDraftEncoding.webMode(draft.mode, category: draft.category),
            purchaseCost: NumericInputFieldSupport.plainNumericString(from: draft.purchaseCostDigits),
            purchaseDate: draft.purchaseDate.map { PropFirmExpenseMoney.dayString(from: $0) } ?? ""
        )
        let body = try transport.encodeJSON(
            Body(brokerIntegrationAccountId: brokerIntegrationAccountId, createAccount: payload)
        )
        return try await post("/api/integrations/rithmic/connections/\(connectionId)/accounts/link", body: body)
    }

    func syncRithmicAccount(
        connectionId: String,
        mappingId: String,
        password: String? = nil
    ) async throws -> TradovateAccountSyncResponse {
        struct Body: Encodable {
            var password: String
        }
        let body: Data
        if let password, !password.isEmpty {
            body = try transport.encodeJSON(Body(password: password))
        } else {
            body = Data()
        }
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/rithmic/connections/\(connectionId)/accounts/\(mappingId)/sync",
            method: .post,
            body: body,
            requiresAuthentication: true
        )
        return try decodeBrokerAccountSync(from: response, context: "rithmic.sync")
    }

    func disconnectRithmic(connectionId: String) async throws {
        let response = try await transport.send(
            host: .bff,
            path: "/api/integrations/rithmic/connections/\(connectionId)/disconnect",
            method: .post,
            body: Data(),
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw brokerError(from: response, fallback: "Could not disconnect Rithmic.")
        }
    }

    // MARK: - HTTP helpers

    private static func optionalTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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

    private func decodeBrokerAccountSync(from response: HTTPResponse, context: String) throws -> TradovateAccountSyncResponse {
        let status = response.statusCode
        BrokerSyncDebugLog.syncHTTP(path: context, status: status, bytes: response.data.count)
        if BrokerSyncFailureResolution.payloadContainsSyncSummary(response.data) {
            do {
                return try transport.decoder.decode(TradovateAccountSyncResponse.self, from: response)
            } catch {
                BrokerIntegrationDebugLog.decodeFailure(context: context, detail: String(describing: error))
                throw AppError.unknown(message: brokerDecodeUserMessage)
            }
        }
        guard status == 200 || status == 400 || status == 409 || (200 ... 299).contains(status) else {
            throw brokerError(from: response, fallback: "Broker request failed (\(status)).")
        }
        do {
            return try transport.decoder.decode(TradovateAccountSyncResponse.self, from: response)
        } catch {
            BrokerIntegrationDebugLog.decodeFailure(context: context, detail: String(describing: error))
            throw AppError.unknown(message: brokerDecodeUserMessage)
        }
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
    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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

    static func rithmicDraft(
        externalAccountId: String,
        externalAccountName: String?,
        externalDisplayName: String?,
        metadata: [String: JSONBrokerValue]
    ) -> TradingAccountDraft {
        let accountIdFromMeta: String = {
            if case .string(let value) = metadata["accountId"] {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }()
        let displayName =
            trimmedNonEmpty(externalAccountName)
            ?? trimmedNonEmpty(externalDisplayName)
            ?? trimmedNonEmpty(accountIdFromMeta)
            ?? trimmedNonEmpty(externalAccountId.split(separator: "|").last.map(String.init))
            ?? "Rithmic account"
        let accountNumber =
            trimmedNonEmpty(accountIdFromMeta)
            ?? trimmedNonEmpty(externalAccountId.split(separator: "|").last.map(String.init))
            ?? externalAccountId
        return TradingAccountDraft(
            name: displayName,
            sizeDigits: "",
            accountNumber: accountNumber,
            category: .personal,
            mode: .live,
            note: "",
            propFirmRules: nil
        )
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
