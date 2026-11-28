import Foundation

#if DEBUG
/// Xcode console filter: `[ProfileInsights]`
nonisolated enum ProfileInsightsDebugLog {
    private static let rpcName = BackendV2Versioning.RPCName.profileInsightsBootstrap.rawValue

    static func logRPCRequest(query: ProfileInsightsQuery, jsonBody: Data) {
        let params = String(data: jsonBody, encoding: .utf8) ?? "len=\(jsonBody.count)"
        log("RPC request name=\(rpcName) query=\(query) parameters=\(params)")
    }

    static func logRPCResponseReceived(byteCount: Int) {
        log("RPC response received bytes=\(byteCount)")
    }

    static func logTransportFailure(_ error: Error) {
        let detail = postgrestDetail(from: error)
        log("RPC transport failed \(detail.telemetrySummary)")
        if let network = underlyingNetworkError(error) {
            switch network {
            case .server(let code, let message):
                log("HTTP status=\(code) body=\(PostgRESTValidationDetail.safeField(message ?? "", max: 240))")
            case .validation(let code, let message):
                log("HTTP status=\(code ?? -1) validation=\(PostgRESTValidationDetail.safeField(message, max: 240))")
            default:
                log("networkError=\(String(describing: network))")
            }
        } else {
            log("errorType=\(type(of: error)) description=\(PostgRESTValidationDetail.safeField(String(describing: error), max: 240))")
        }
    }

    static func logDecodeFailure(_ error: Error, payloadBytes: Int) {
        if let decoding = error as? DecodingError {
            let snap = BackendV2DecodingDiagnostics.snapshot(from: decoding)
            let summary = BackendV2DecodingDiagnostics.telemetrySummary(from: decoding)
            log("decode failed payloadBytes=\(payloadBytes) \(summary)")
            if let snap {
                if let key = snap.missingKey {
                    log("decode missingKey=\(key) path=\(snap.codingPath)")
                } else {
                    log("decode category=\(snap.category) path=\(snap.codingPath) expected=\(snap.expectedType ?? "n/a")")
                }
            }
            return
        }
        log("decode failed non-DecodingError payloadBytes=\(payloadBytes) error=\(PostgRESTValidationDetail.safeField(String(describing: error), max: 240))")
    }

    /// Top-level contract keys only (no `viewer_id`, no series values).
    static func logContractProbe(payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            log("contract probe: payload is not a JSON object")
            return
        }

        var issues: [String] = []
        if object["meta"] == nil { issues.append("missing meta") }
        if object["data"] == nil { issues.append("missing data") }

        if let meta = object["meta"] as? [String: Any] {
            for key in ["contract_version", "days", "viewer_id"] where meta[key] == nil {
                issues.append("meta.\(key) missing")
            }
            if let version = meta["contract_version"] as? String, version != "v1" {
                issues.append("meta.contract_version=\(version) expected v1")
            }
            if meta["days"] is NSNumber == false, meta["days"] is Int == false {
                issues.append("meta.days wrongType")
            }
        } else if object["meta"] != nil {
            issues.append("meta wrongType")
        }

        if let data = object["data"] as? [String: Any] {
            for key in ["coverage", "period", "summary", "summary_prior", "series"] where data[key] == nil {
                issues.append("data.\(key) missing")
            }
            if let period = data["period"] as? [String: Any] {
                for key in ["start", "end", "prior_start", "prior_end"] where period[key] as? String == nil {
                    issues.append("data.period.\(key) missingOrNotString")
                }
            }
        } else if object["data"] != nil {
            issues.append("data wrongType")
        }

        if issues.isEmpty {
            log("contract probe: matches ProfileInsightsBootstrapV1 top-level shape")
        } else {
            log("contract probe: mismatches Swift model — \(issues.joined(separator: "; "))")
        }
    }

    static func logViewModelFailure(query: ProfileInsightsQuery, error: Error) {
        if error is DecodingError {
            log("load failed query=\(query) phase=decode (see repository decode logs)")
        } else {
            log("load failed query=\(query) \(postgrestDetail(from: error).telemetrySummary)")
        }
    }

    static func logViewModelSuccess(days: Int, contractVersion: String) {
        log("load succeeded days=\(days) contract_version=\(contractVersion)")
    }

    private static func log(_ message: String) {
        print("[ProfileInsights] \(message)")
    }

    private static func postgrestDetail(from error: Error) -> PostgRESTValidationDetail {
        if let app = error as? AppError, case .transport(let network) = app {
            return postgrestDetail(from: network)
        }
        if let network = error as? NetworkError {
            return postgrestDetail(from: network)
        }
        if let app = error as? AppError, case .unknown(let message) = app {
            return PostgRESTValidationDetail.parse(httpStatus: nil, body: message)
        }
        return PostgRESTValidationDetail.parse(httpStatus: nil, body: String(describing: error))
    }

    private static func postgrestDetail(from network: NetworkError) -> PostgRESTValidationDetail {
        switch network {
        case .server(let status, let message):
            return PostgRESTValidationDetail.parse(httpStatus: status, body: message ?? "")
        case .validation(let status, let message):
            return PostgRESTValidationDetail.parse(httpStatus: status, body: message)
        default:
            return PostgRESTValidationDetail(httpStatus: nil, code: nil, message: String(describing: network), details: nil, hint: nil)
        }
    }

    private static func underlyingNetworkError(_ error: Error) -> NetworkError? {
        if let network = error as? NetworkError { return network }
        if let app = error as? AppError, case .transport(let network) = app { return network }
        return nil
    }
}
#endif