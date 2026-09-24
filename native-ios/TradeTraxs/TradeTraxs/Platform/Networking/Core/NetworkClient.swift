import Foundation

/// Primary networking surface used by future repositories / services.
nonisolated protocol NetworkClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse

    func send<T: Decodable & Sendable>(
        _ request: HTTPRequest,
        decodeAs type: T.Type
    ) async throws -> T

    /// Applies the same request interceptors as ``send(_:)`` (auth, Supabase headers, logging).
    func prepare(_ request: HTTPRequest) async throws -> HTTPRequest

    /// Streaming bytes for large payloads / progressive downloads.
    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, URLResponse)
}

/// URLSession-backed client with interceptors, retries, metrics, cancellation.
actor URLSessionNetworkClient: NetworkClient {
    private let session: URLSession
    private let requestInterceptor: any RequestInterceptor
    private let responseInterceptor: any ResponseInterceptor
    private let retryPolicy: RetryPolicy
    private let errorMapper: NetworkErrorMapper
    private let decoder: any ResponseDecoding
    private let metricsRecorder: (any RequestMetricsRecording)?
    private let reachability: (any ReachabilityMonitoring)?

    init(
        session: URLSession,
        requestInterceptor: any RequestInterceptor,
        responseInterceptor: any ResponseInterceptor,
        retryPolicy: RetryPolicy,
        errorMapper: NetworkErrorMapper = NetworkErrorMapper(),
        decoder: any ResponseDecoding = JSONResponseDecoder(),
        metricsRecorder: (any RequestMetricsRecording)? = nil,
        reachability: (any ReachabilityMonitoring)? = nil
    ) {
        self.session = session
        self.requestInterceptor = requestInterceptor
        self.responseInterceptor = responseInterceptor
        self.retryPolicy = retryPolicy
        self.errorMapper = errorMapper
        self.decoder = decoder
        self.metricsRecorder = metricsRecorder
        self.reachability = reachability
    }

    func prepare(_ request: HTTPRequest) async throws -> HTTPRequest {
        try await requestInterceptor.intercept(request)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 1
        var unauthorizedRecoveryAttempted = false
        var current = try await prepare(request)

        while true {
            try throwIfCancelled(requestPath: current.url.path)
            try throwIfOffline()

            var metrics = RequestMetrics(
                requestID: UUID(),
                method: current.method,
                path: current.url.path,
                host: current.endpoint.host,
                startedAt: Date(),
                endedAt: nil,
                statusCode: nil,
                byteCountSent: Int64(current.body?.count ?? 0),
                byteCountReceived: 0,
                attempt: attempt,
                errorDescription: nil
            )

            do {
                let priority = current.schedulingPriority
                let path = current.url.path
                let host = current.endpoint.host.rawValue
                let isAuthTokenRefresh = Self.isAuthTokenRefreshRequest(path: path, method: current.method)
                if isAuthTokenRefresh {
                    AuthRefreshTiming.operationStarted(path: path, generation: nil)
                    AuthRefreshTiming.concurrencyAcquireRequested(path: path, priority: priority)
                }
                let inFlightAtStart = await NetworkConcurrencyCoordinator.shared.snapshot().total
                let transportStarted = CFAbsoluteTimeGetCurrent()
                let urlRequest = current.urlRequest
                let (data, response, taskMetrics) = try await NetworkConcurrencyCoordinator.shared.runWithSlot(
                    priority: priority,
                    path: path,
                    host: host,
                    method: current.method
                ) {
                    if isAuthTokenRefresh {
                        AuthRefreshTiming.concurrencyAcquired(path: path, priority: priority)
                        AuthRefreshTiming.urlTaskCreated(path: path)
                        AuthRefreshTiming.urlTaskResumed(path: path)
                    }
                    let result = try await session.dataWithTaskMetrics(for: urlRequest)
                    if isAuthTokenRefresh,
                       let http = result.1 as? HTTPURLResponse
                    {
                        AuthRefreshTiming.responseReceived(path: path, statusCode: http.statusCode)
                    }
                    return result
                }
                if isAuthTokenRefresh {
                    let totalMs = Int((CFAbsoluteTimeGetCurrent() - transportStarted) * 1_000)
                    AuthRefreshTiming.operationCompleted(
                        path: path,
                        outcome: "transport",
                        durationMs: totalMs
                    )
                }
                #if DEBUG
                NetworkTaskMetricsProbe.logRPCIfPresent(
                    path: path,
                    metrics: taskMetrics
                )
                let totalMs = (CFAbsoluteTimeGetCurrent() - transportStarted) * 1000
                if totalMs >= 2000 {
                    let responseWaitMs = NetworkTaskMetricsProbe.responseWaitMilliseconds(metrics: taskMetrics)
                    NetworkConcurrencyProbe.logSlowRequest(
                        host: host,
                        path: path,
                        priority: priority,
                        inFlightAtStart: inFlightAtStart,
                        totalMs: totalMs,
                        responseWaitMs: responseWaitMs
                    )
                }
                #endif
                if let mapped = errorMapper.map(data: data, response: response, error: nil) {
                    metrics.endedAt = Date()
                    metrics.statusCode = (response as? HTTPURLResponse)?.statusCode
                    metrics.errorDescription = String(describing: mapped)
                    metricsRecorder?.record(metrics)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        let totalMs = (CFAbsoluteTimeGetCurrent() - transportStarted) * 1000
                        SupabaseRPCFailureLog.logHTTPFailure(
                            path: path,
                            method: current.method.rawValue,
                            statusCode: http.statusCode,
                            body: data,
                            requestID: metrics.requestID,
                            elapsedMs: totalMs
                        )
                    }

                    if case .unauthorized = mapped,
                       current.endpoint.requiresAuthentication,
                       !unauthorizedRecoveryAttempted
                    {
                        unauthorizedRecoveryAttempted = true
                        let recovery = await NetworkUnauthorizedRecovery.shared.recoverFromUnauthorized()
                        switch recovery {
                        case .recovered:
                            current = try await prepare(request)
                            continue
                        case .failedTransient, .noHandler:
                            break
                        case .sessionEnded:
                            break
                        }
                    }

                    if retryPolicy.shouldRetry(request: current, error: mapped, attempt: attempt) {
                        let delay = retryPolicy.delay(forAttempt: attempt, error: mapped)
                        attempt += 1
                        try await sleep(delay)
                        current = try await requestInterceptor.intercept(request)
                        continue
                    }
                    throw mapped
                }

                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.unknown(message: "Missing HTTPURLResponse")
                }

                let raw = HTTPResponse(data: data, httpURLResponse: http, metrics: nil)
                let intercepted = try await responseInterceptor.intercept(raw, for: current)

                metrics.endedAt = Date()
                metrics.statusCode = intercepted.statusCode
                metrics.byteCountReceived = Int64(intercepted.data.count)
                let finalized = HTTPResponse(
                    data: intercepted.data,
                    httpURLResponse: intercepted.httpURLResponse,
                    metrics: metrics
                )
                metricsRecorder?.record(metrics)
                return finalized
            } catch let networkError as NetworkError {
                metrics.endedAt = Date()
                metrics.errorDescription = String(describing: networkError)
                metricsRecorder?.record(metrics)

                if retryPolicy.shouldRetry(request: current, error: networkError, attempt: attempt) {
                    let delay = retryPolicy.delay(forAttempt: attempt, error: networkError)
                    attempt += 1
                    try await sleep(delay)
                    current = try await requestInterceptor.intercept(request)
                    continue
                }
                throw networkError
            } catch {
                if let cancelled = NetworkTaskCancellation.mapIfCancelled(error) {
                    metrics.endedAt = Date()
                    metrics.errorDescription = cancelled.localizedDescription
                    metricsRecorder?.record(metrics)
                    #if DEBUG
                    NetworkCancelDiagnostics.log(
                        requestPath: current.url.path,
                        reason: cancelled.localizedDescription,
                        cancelSource: "transport"
                    )
                    if Self.isAuthTokenRefreshRequest(path: current.url.path, method: current.method) {
                        AuthLifecycleTrace.log(
                            operation: "network.tokenExchange",
                            authGeneration: AuthLifecycleGeneration.current(),
                            requestPath: current.url.path,
                            decision: "cancelled",
                            reason: cancelled.localizedDescription,
                            cancelInitiatorGeneration: await NetworkConcurrencyCoordinator.shared
                                .currentSessionEndGeneration()
                        )
                    }
                    #endif
                    throw cancelled
                }

                let mapped = errorMapper.mapTransport(error)
                metrics.endedAt = Date()
                metrics.errorDescription = String(describing: mapped)
                metricsRecorder?.record(metrics)

                if retryPolicy.shouldRetry(request: current, error: mapped, attempt: attempt) {
                    let delay = retryPolicy.delay(forAttempt: attempt, error: mapped)
                    attempt += 1
                    try await sleep(delay)
                    current = try await requestInterceptor.intercept(request)
                    continue
                }
                throw mapped
            }
        }
    }

    func send<T: Decodable & Sendable>(
        _ request: HTTPRequest,
        decodeAs type: T.Type
    ) async throws -> T {
        let response = try await send(request)
        return try decoder.decode(type, from: response)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try throwIfCancelled(requestPath: request.url.path)
        try throwIfOffline()
        let current = try await requestInterceptor.intercept(request)
        let priority = current.schedulingPriority
        let path = current.url.path
        let host = current.endpoint.host.rawValue
        let urlRequest = current.urlRequest
        do {
            return try await NetworkConcurrencyCoordinator.shared.runWithSlot(
                priority: priority,
                path: path,
                host: host,
                method: current.method
            ) {
                try await session.bytes(for: urlRequest)
            }
        } catch {
            if let cancelled = NetworkTaskCancellation.mapIfCancelled(error) {
                throw cancelled
            }
            throw errorMapper.mapTransport(error)
        }
    }

    private func throwIfCancelled(requestPath: String) throws {
        do {
            try NetworkTaskCancellation.check()
        } catch {
            #if DEBUG
            NetworkCancelDiagnostics.log(
                requestPath: requestPath,
                reason: "Task.checkCancellation",
                cancelSource: "NetworkClient.send"
            )
            #endif
            throw NetworkError.cancelled
        }
    }

    private func throwIfOffline() throws {
        if let reachability, !reachability.isOnline {
            throw NetworkError.connectivity
        }
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func isAuthTokenRefreshRequest(path: String, method: HTTPMethod) -> Bool {
        path.hasPrefix("/auth/v1/token") && method == .post
    }
}

/// Non-actor convenience wrapper for call sites that prefer value types.
nonisolated struct NetworkClientBox: NetworkClient {
    private let client: URLSessionNetworkClient

    init(client: URLSessionNetworkClient) {
        self.client = client
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await client.send(request)
    }

    func send<T: Decodable>(_ request: HTTPRequest, decodeAs type: T.Type) async throws -> T {
        try await client.send(request, decodeAs: type)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await client.bytes(for: request)
    }

    func prepare(_ request: HTTPRequest) async throws -> HTTPRequest {
        try await client.prepare(request)
    }
}
