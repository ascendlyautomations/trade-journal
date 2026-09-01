import Foundation

/// Typed Backend V2 RPC errors.
nonisolated enum BackendV2RPCError: Error, Sendable, Equatable {
    case cancelled
    case unknownRPCName(String)
    /// HTTP / PostgREST request rejected before a decodable bootstrap payload (4xx body).
    case requestValidation(PostgRESTValidationDetail)
    case transport(String)
    case decode(String)
    case contractVersionMismatch(expected: String, got: String)
    case notImplemented(String)

    var code: String {
        switch self {
        case .cancelled: return "cancelled"
        case .unknownRPCName: return "validation"
        case .requestValidation: return "validation"
        case .transport: return "rpc_error"
        case .decode: return "decode"
        case .contractVersionMismatch: return "contract_version"
        case .notImplemented: return "not_implemented"
        }
    }
}

/// Options for a Backend V2 RPC invocation.
nonisolated struct BackendV2RPCCallOptions: Sendable {
    var cacheHit: Bool?
    var cacheMiss: Bool?
    var flagName: String?

    init(cacheHit: Bool? = nil, cacheMiss: Bool? = nil, flagName: String? = nil) {
        self.cacheHit = cacheHit
        self.cacheMiss = cacheMiss
        self.flagName = flagName
    }
}

/**
 Typed Backend V2 RPC client built on the existing ``RPCClient`` transport.
 Phase 1: not wired into CompositionRoot / screens.
 */
nonisolated struct BackendV2RPCClient: Sendable {
    private let transport: any RPCClient
    private let enforceKnownNames: Bool
    private let decoder: JSONDecoder

    init(
        transport: any RPCClient,
        enforceKnownNames: Bool = true,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.transport = transport
        self.enforceKnownNames = enforceKnownNames
        self.decoder = decoder
    }

    func call<T: Decodable>(
        _ name: BackendV2Versioning.RPCName,
        argumentsJSON: Data = Data("{}".utf8),
        as type: T.Type,
        options: BackendV2RPCCallOptions = .init()
    ) async throws -> T {
        try await call(
            name.rawValue,
            argumentsJSON: argumentsJSON,
            as: type,
            options: options
        )
    }

    func call<T: Decodable>(
        _ name: String,
        argumentsJSON: Data = Data("{}".utf8),
        as type: T.Type,
        options: BackendV2RPCCallOptions = .init()
    ) async throws -> T {
        if enforceKnownNames, !BackendV2Versioning.isKnownRPCName(name) {
            throw BackendV2RPCError.unknownRPCName(name)
        }

        let correlation = BackendV2RpcStageTracer.begin(name)
        BackendV2RpcStageTracer.trace(name, stage: "request.started", correlation: correlation)

        let execStart = ContinuousClock.now
        var decodeMs: Double?
        var payloadBytes: Int?
        var errorCode: String?

        do {
            BackendV2RpcStageTracer.trace(name, stage: "transport.await", correlation: correlation)
            let data = try await transport.call(
                functionName: name,
                jsonBody: argumentsJSON
            )
            BackendV2RpcStageTracer.trace(
                name,
                stage: "body.read.completed",
                correlation: correlation,
                detail: "bytes=\(data.count)"
            )
            payloadBytes = data.count
            BackendV2RpcStageTracer.trace(name, stage: "decoder.started", correlation: correlation)
            let decodeStart = ContinuousClock.now
            let value: T
            do {
                value = try decoder.decode(T.self, from: data)
            } catch let decodingError as DecodingError {
                BackendV2DecodingDiagnostics.trace(
                    rpcName: name,
                    correlation: correlation,
                    error: decodingError
                )
                errorCode = BackendV2RPCError.decode("").code
                throw decodingError
            } catch {
                BackendV2RpcStageTracer.trace(name, stage: "decoder.failed", correlation: correlation)
                errorCode = BackendV2RPCError.decode("").code
                throw BackendV2RPCError.decode(String(describing: error))
            }
            decodeMs = durationMilliseconds(from: decodeStart)
            BackendV2RpcStageTracer.trace(name, stage: "decoder.completed", correlation: correlation)
            BackendV2RpcStageTracer.trace(name, stage: "single-flight.completed", correlation: correlation)
            let executionMs = durationMilliseconds(from: execStart)
            BackendV2Telemetry.record(
                BackendV2TelemetryEvent(
                    rpcName: name,
                    success: true,
                    executionMs: executionMs,
                    decodeMs: decodeMs,
                    payloadBytes: payloadBytes,
                    cacheHit: options.cacheHit,
                    cacheMiss: options.cacheMiss,
                    errorCode: nil,
                    flagName: options.flagName
                )
            )
            return value
        } catch {
            let mapped = Self.mapFailure(error, rpcName: name, correlation: correlation)
            errorCode = mapped.code
            BackendV2Telemetry.record(
                BackendV2TelemetryEvent(
                    rpcName: name,
                    success: false,
                    executionMs: durationMilliseconds(from: execStart),
                    decodeMs: decodeMs,
                    payloadBytes: payloadBytes,
                    cacheHit: options.cacheHit,
                    cacheMiss: options.cacheMiss,
                    errorCode: errorCode,
                    flagName: options.flagName
                )
            )
            throw mapped
        }
    }

    private static func mapFailure(
        _ error: Error,
        rpcName: String,
        correlation: String
    ) -> BackendV2RPCError {
        if let rpc = error as? BackendV2RPCError {
            if case .requestValidation(let detail) = rpc {
                BackendV2RpcStageTracer.trace(
                    rpcName,
                    stage: "transport.failed",
                    correlation: correlation,
                    detail: detail.telemetrySummary
                )
            }
            return rpc
        }
        if error is CancellationError {
            BackendV2RpcStageTracer.trace(rpcName, stage: "cancellation.received", correlation: correlation)
            return .cancelled
        }
        if let detail = validationDetail(from: error) {
            BackendV2RpcStageTracer.trace(
                rpcName,
                stage: "transport.failed",
                correlation: correlation,
                detail: detail.telemetrySummary
            )
            return .requestValidation(detail)
        }
        let summary = MessagesBootstrapFailureDiagnostic.make(error: error).summary
        BackendV2RpcStageTracer.trace(
            rpcName,
            stage: "transport.failed",
            correlation: correlation,
            detail: summary
        )
        return .transport(summary)
    }

    private static func validationDetail(from error: Error) -> PostgRESTValidationDetail? {
        if let app = error as? AppError, case .transport(let network) = app {
            return validationDetail(from: network)
        }
        if let network = error as? NetworkError {
            return validationDetail(from: network)
        }
        return nil
    }

    private static func validationDetail(from network: NetworkError) -> PostgRESTValidationDetail? {
        if case .validation(let statusCode, let message) = network {
            return PostgRESTValidationDetail.parse(httpStatus: statusCode, body: message)
        }
        return nil
    }

    private func durationMilliseconds(from start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }
}
