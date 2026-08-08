import Foundation

/// Primary networking surface used by future repositories / services.
nonisolated protocol NetworkClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse

    func send<T: Decodable>(
        _ request: HTTPRequest,
        decodeAs type: T.Type
    ) async throws -> T

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

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 1
        var current = try await requestInterceptor.intercept(request)

        while true {
            try throwIfCancelled()
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
                let (data, response) = try await session.data(for: current.urlRequest)
                if let mapped = errorMapper.map(data: data, response: response, error: nil) {
                    metrics.endedAt = Date()
                    metrics.statusCode = (response as? HTTPURLResponse)?.statusCode
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

    func send<T: Decodable>(
        _ request: HTTPRequest,
        decodeAs type: T.Type
    ) async throws -> T {
        let response = try await send(request)
        return try decoder.decode(type, from: response)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try throwIfCancelled()
        try throwIfOffline()
        let current = try await requestInterceptor.intercept(request)
        do {
            return try await session.bytes(for: current.urlRequest)
        } catch {
            if let cancelled = NetworkTaskCancellation.mapIfCancelled(error) {
                throw cancelled
            }
            throw errorMapper.mapTransport(error)
        }
    }

    private func throwIfCancelled() throws {
        do {
            try NetworkTaskCancellation.check()
        } catch {
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
}
