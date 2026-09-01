import Foundation

/// Classifies Backend V2 RPC failures for controlled fallback (Native Batch N1).
nonisolated enum BackendV2RpcCompat {
    /// RPC function absent from PostgREST schema — safe to fall back once per app session.
    static func isRpcUnavailable(_ error: Error, rpcName: String) -> Bool {
        let text = errorText(error).lowercased()
        let name = rpcName.lowercased()

        if text.contains("pgrst202") { return text.contains(name) || text.contains("could not find") }

        if text.contains("42883") || text.contains("42p01") {
            let missingFunction =
                text.contains("function") &&
                (text.contains("does not exist") ||
                    text.contains("could not find") ||
                    text.contains("undefined_function"))
            return missingFunction && text.contains(name)
        }

        if text.contains(name),
           text.contains("could not find the function") || text.contains("could not find function")
        {
            return true
        }

        if let backend = error as? BackendV2RPCError {
            switch backend {
            case .contractVersionMismatch:
                return true
            case .notImplemented:
                return true
            default:
                break
            }
        }

        return false
    }

    /// Network / 5xx / auth — never auto fan-out to legacy REST.
    static func isTransientFailure(_ error: Error, rpcName: String) -> Bool {
        if isRpcUnavailable(error, rpcName: rpcName) { return false }

        if error is CancellationError { return true }
        if case BackendV2RPCError.cancelled = error { return true }

        if let network = underlyingNetworkError(error) {
            switch network {
            case .connectivity, .timeout, .rateLimited:
                return true
            case .server(let code, _):
                return code >= 500
            case .unauthorized, .forbidden:
                return true
            default:
                return false
            }
        }

        let text = errorText(error).lowercased()
        if text.contains("401") || text.contains("403") { return true }
        if text.contains("500") || text.contains("502") || text.contains("503") { return true }
        return false
    }

    private static func errorText(_ error: Error) -> String {
        if let backend = error as? BackendV2RPCError {
            switch backend {
            case .transport(let message), .decode(let message), .notImplemented(let message):
                return message
            case .requestValidation(let detail):
                return detail.telemetrySummary
            case .contractVersionMismatch(let expected, let got):
                return "contract_version expected=\(expected) got=\(got)"
            case .cancelled:
                return "cancelled"
            case .unknownRPCName(let name):
                return "unknown rpc \(name)"
            }
        }
        return String(describing: error)
    }

    private static func underlyingNetworkError(_ error: Error) -> NetworkError? {
        if let network = error as? NetworkError { return network }
        if case BackendV2RPCError.transport = error { return .connectivity }
        if let app = error as? AppError, case .transport(let network) = app {
            return network
        }
        return nil
    }
}

/// Per-viewer RPC availability — avoids repeated failed calls after confirmed missing RPC.
actor BackendV2RpcAvailability {
    static let shared = BackendV2RpcAvailability()

    private var unavailable: Set<String> = []

    func isUnavailable(rpcName: String, viewerID: String) -> Bool {
        unavailable.contains(key(rpcName: rpcName, viewerID: viewerID))
    }

    func markUnavailable(rpcName: String, viewerID: String) {
        unavailable.insert(key(rpcName: rpcName, viewerID: viewerID))
    }

    func clear(viewerID: String? = nil) {
        if let viewerID {
            unavailable = unavailable.filter { !$0.hasPrefix("\(viewerID)|") }
        } else {
            unavailable.removeAll()
        }
    }

    private func key(rpcName: String, viewerID: String) -> String {
        "\(viewerID)|\(rpcName)"
    }
}
