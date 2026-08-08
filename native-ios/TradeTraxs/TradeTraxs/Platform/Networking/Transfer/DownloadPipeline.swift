import Foundation

/// Destination for streamed / file downloads.
nonisolated enum DownloadDestination: Sendable {
    case memory
    case temporaryFile
    case file(URL)
}

nonisolated struct DownloadResult: Sendable {
    let data: Data?
    let fileURL: URL?
    let response: HTTPResponse
}

/// File download helpers using URLSession (compatible with image pipelines later).
nonisolated struct DownloadPipeline: Sendable {
    private let session: URLSession
    private let errorMapper = NetworkErrorMapper()

    init(session: URLSession) {
        self.session = session
    }

    func download(
        _ request: HTTPRequest,
        to destination: DownloadDestination = .temporaryFile
    ) async throws -> DownloadResult {
        try NetworkTaskCancellation.check()

        switch destination {
        case .memory:
            let (data, urlResponse) = try await session.data(for: request.urlRequest)
            if let error = errorMapper.map(data: data, response: urlResponse, error: nil) {
                throw error
            }
            guard let http = urlResponse as? HTTPURLResponse else {
                throw NetworkError.unknown(message: "Missing HTTPURLResponse")
            }
            let response = HTTPResponse(data: data, httpURLResponse: http, metrics: nil)
            return DownloadResult(data: data, fileURL: nil, response: response)

        case .temporaryFile, .file:
            let (tempURL, urlResponse) = try await session.download(for: request.urlRequest)
            if let error = errorMapper.map(data: nil, response: urlResponse, error: nil) {
                throw error
            }
            guard let http = urlResponse as? HTTPURLResponse else {
                throw NetworkError.unknown(message: "Missing HTTPURLResponse")
            }

            let finalURL: URL
            switch destination {
            case .file(let url):
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tempURL, to: url)
                finalURL = url
            default:
                finalURL = tempURL
            }

            let response = HTTPResponse(data: Data(), httpURLResponse: http, metrics: nil)
            return DownloadResult(data: nil, fileURL: finalURL, response: response)
        }
    }
}
