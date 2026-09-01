import Foundation

/// Privacy-safe classification for Messages bootstrap / transport failures.
nonisolated enum MessagesBootstrapErrorKind: String, Sendable {
    case cancelled
    case timedOut
    case network
    case http
    case auth
    case decode
    case contract
    case compatibility
    case validation
    case intentionalCancellation
    case unknown
}

nonisolated struct MessagesBootstrapFailureDiagnostic: Sendable {
    var errorKind: MessagesBootstrapErrorKind
    var urlErrorCode: Int?
    var httpStatus: Int?
    var taskCancelled: Bool
    var isTerminal: Bool
    var isTransient: Bool
    var summary: String

    static func make(error: Error, taskCancelled: Bool = Task.isCancelled) -> MessagesBootstrapFailureDiagnostic {
        if taskCancelled || error is CancellationError {
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .intentionalCancellation,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: true,
                isTerminal: false,
                isTransient: false,
                summary: "intentionalCancellation"
            )
        }

        if let rpc = error as? BackendV2RPCError {
            switch rpc {
            case .cancelled:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .cancelled,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: false,
                    summary: "rpcCancelled"
                )
            case .requestValidation(let detail):
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .validation,
                    urlErrorCode: nil,
                    httpStatus: detail.httpStatus,
                    taskCancelled: taskCancelled,
                    isTerminal: true,
                    isTransient: false,
                    summary: detail.telemetrySummary
                )
            case .transport(let message):
                let lowered = message.lowercased()
                if lowered.contains("timeout") || lowered.contains("timed out") {
                    return MessagesBootstrapFailureDiagnostic(
                        errorKind: .timedOut,
                        urlErrorCode: nil,
                        httpStatus: nil,
                        taskCancelled: taskCancelled,
                        isTerminal: false,
                        isTransient: true,
                        summary: "transportTimeout"
                    )
                }
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .network,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: true,
                    summary: "transport"
                )
            case .decode:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .decode,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: true,
                    isTransient: false,
                    summary: "decode"
                )
            case .contractVersionMismatch:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .contract,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: true,
                    isTransient: false,
                    summary: "contractVersion"
                )
            case .unknownRPCName, .notImplemented:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .compatibility,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: true,
                    isTransient: false,
                    summary: "compatibility"
                )
            }
        }

        if let app = error as? AppError {
            switch app {
            case .cancelled:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .intentionalCancellation,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: true,
                    isTerminal: false,
                    isTransient: false,
                    summary: "appCancelled"
                )
            case .transport(let network):
                return make(networkError: network, taskCancelled: taskCancelled)
            case .authentication:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .auth,
                    urlErrorCode: nil,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: true,
                    isTransient: false,
                    summary: "auth"
                )
            default:
                break
            }
        }

        if let network = error as? NetworkError {
            return make(networkError: network, taskCancelled: taskCancelled)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = nsError.code
            switch code {
            case NSURLErrorCancelled:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .cancelled,
                    urlErrorCode: code,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: false,
                    summary: "urlCancelled"
                )
            case NSURLErrorTimedOut:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .timedOut,
                    urlErrorCode: code,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: true,
                    summary: "urlTimedOut"
                )
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .network,
                    urlErrorCode: code,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: true,
                    summary: "urlNetwork"
                )
            default:
                return MessagesBootstrapFailureDiagnostic(
                    errorKind: .network,
                    urlErrorCode: code,
                    httpStatus: nil,
                    taskCancelled: taskCancelled,
                    isTerminal: false,
                    isTransient: true,
                    summary: "urlError\(code)"
                )
            }
        }

        return MessagesBootstrapFailureDiagnostic(
            errorKind: .unknown,
            urlErrorCode: nil,
            httpStatus: nil,
            taskCancelled: taskCancelled,
            isTerminal: false,
            isTransient: true,
            summary: "unknown"
        )
    }

    private static func make(networkError: NetworkError, taskCancelled: Bool) -> MessagesBootstrapFailureDiagnostic {
        switch networkError {
        case .cancelled:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .cancelled,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: false,
                isTransient: false,
                summary: "networkCancelled"
            )
        case .timeout:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .timedOut,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: false,
                isTransient: true,
                summary: "networkTimeout"
            )
        case .connectivity:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .network,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: false,
                isTransient: true,
                summary: "offline"
            )
        case .unauthorized, .forbidden:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .auth,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: true,
                isTransient: false,
                summary: "auth"
            )
        case .server(let status, _):
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .http,
                urlErrorCode: nil,
                httpStatus: status,
                taskCancelled: taskCancelled,
                isTerminal: false,
                isTransient: status >= 500,
                summary: "http\(status)"
            )
        case .decoding:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .decode,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: true,
                isTransient: false,
                summary: "decode"
            )
        case .validation(let statusCode, let message):
            let detail = PostgRESTValidationDetail.parse(httpStatus: statusCode, body: message)
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .validation,
                urlErrorCode: nil,
                httpStatus: detail.httpStatus,
                taskCancelled: taskCancelled,
                isTerminal: true,
                isTransient: false,
                summary: detail.telemetrySummary
            )
        default:
            return MessagesBootstrapFailureDiagnostic(
                errorKind: .unknown,
                urlErrorCode: nil,
                httpStatus: nil,
                taskCancelled: taskCancelled,
                isTerminal: false,
                isTransient: true,
                summary: "networkUnknown"
            )
        }
    }

    var isBenignForUI: Bool {
        errorKind == .intentionalCancellation || errorKind == .cancelled
    }
}
