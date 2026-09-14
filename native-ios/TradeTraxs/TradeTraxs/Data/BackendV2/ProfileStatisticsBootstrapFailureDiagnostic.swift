import Foundation

#if DEBUG
nonisolated enum ProfileStatisticsBootstrapFailureDiagnostic {
    static func log(rpcName: String, error: Error) {
        if error is CancellationError { return }
        if case BackendV2RPCError.cancelled = error { return }

        var lines: [String] = ["[ProfileStatisticsBootstrap] rpc=\(rpcName)"]

        if let rpc = error as? BackendV2RPCError {
            switch rpc {
            case .requestValidation(let detail):
                lines.append("kind=requestValidation")
                if let status = detail.httpStatus {
                    lines.append("httpStatus=\(status)")
                }
                if let code = detail.code, !code.isEmpty {
                    lines.append("postgresCode=\(code)")
                }
                if let message = detail.message, !message.isEmpty {
                    lines.append("message=\(message)")
                }
                if let details = detail.details, !details.isEmpty {
                    lines.append("details=\(details)")
                }
                if let hint = detail.hint, !hint.isEmpty {
                    lines.append("hint=\(hint)")
                }
                lines.append("summary=\(detail.telemetrySummary)")
            case .transport(let message):
                lines.append("kind=transport message=\(message)")
            case .decode(let message):
                lines.append("kind=decode message=\(message)")
            case .contractVersionMismatch(let expected, let got):
                lines.append("kind=contractVersionMismatch expected=\(expected) got=\(got)")
            case .unknownRPCName(let name):
                lines.append("kind=unknownRPCName name=\(name)")
            case .notImplemented(let name):
                lines.append("kind=notImplemented name=\(name)")
            case .cancelled:
                return
            }
        } else if let decoding = error as? DecodingError {
            lines.append("kind=decodingError \(String(describing: decoding))")
        } else {
            lines.append("kind=\(type(of: error)) message=\(error.localizedDescription)")
        }

        print(lines.joined(separator: " "))
    }
}
#endif
