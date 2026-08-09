import Foundation

/// Maps URLSession / HTTP outcomes into ``NetworkError``.
nonisolated struct NetworkErrorMapper: Sendable {
    func map(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> NetworkError? {
        if let error {
            return mapTransport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            return .unknown(message: "Missing HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return nil
        case 401:
            return .unauthorized
        case 403:
            // Preserve PostgREST/RLS bodies (e.g. 42501). Empty 403 stays forbidden.
            if let message = data.flatMap({ String(data: $0, encoding: .utf8) }),
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return .validation(message: message)
            }
            return .forbidden
        case 408:
            return .timeout
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500..<600:
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            return .server(statusCode: http.statusCode, message: message)
        case 400..<500:
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Request failed"
            return .validation(message: message)
        default:
            return .unknown(message: "Unexpected status \(http.statusCode)")
        }
    }

    func mapTransport(_ error: Error) -> NetworkError {
        if error is CancellationError {
            return .cancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return .connectivity
            default:
                break
            }
        }

        return .unknown(message: error.localizedDescription)
    }

    func mapDecoding(_ error: Error) -> NetworkError {
        .decoding(message: String(describing: error))
    }
}
