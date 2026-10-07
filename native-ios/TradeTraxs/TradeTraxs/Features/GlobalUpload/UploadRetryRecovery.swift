import Foundation

/// Phase 1 retry/recovery — transport failures where the server may have committed work.
enum UploadRetryRecovery {
    static func isAmbiguousTransportFailure(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                switch network {
                case .cancelled, .timeout, .connectivity:
                    return true
                default:
                    return false
                }
            case .cancelled:
                return true
            default:
                return false
            }
        }
        if let network = error as? NetworkError {
            switch network {
            case .cancelled, .timeout, .connectivity:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorCancelled,
             NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }
}

enum UploadJobMediaRetention {
    /// Copies video into a job-scoped temp file so Retry can reuse it while the process stays alive.
    nonisolated static func copyVideoForRetryJob(source: URL, jobID: String, prefix: String) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(jobID).\(ext)", isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
