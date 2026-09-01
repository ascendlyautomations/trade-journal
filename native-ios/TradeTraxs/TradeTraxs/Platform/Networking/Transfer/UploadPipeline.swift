import Foundation

/// Describes an upload body without performing I/O against product endpoints.
nonisolated enum UploadBody: Sendable {
    case data(Data, contentType: String)
    case file(URL, contentType: String)
    case multipart(MultipartFormData)
}

nonisolated struct MultipartFormData: Sendable {
    struct Part: Sendable {
        var name: String
        var fileName: String?
        var mimeType: String?
        var data: Data
    }

    var boundary: String
    var parts: [Part]

    init(boundary: String = "tt-\(UUID().uuidString)", parts: [Part]) {
        self.boundary = boundary
        self.parts = parts
    }

    func encode() -> (data: Data, contentType: String) {
        var body = Data()
        let lineBreak = "\r\n"

        for part in parts {
            body.append("--\(boundary)\(lineBreak)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append(disposition + lineBreak)
            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType)\(lineBreak)")
            }
            body.append(lineBreak)
            body.append(part.data)
            body.append(lineBreak)
        }
        body.append("--\(boundary)--\(lineBreak)")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}

private nonisolated extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

/// Builds upload-capable ``HTTPRequest`` values (no network execution by itself).
nonisolated struct UploadPipeline: Sendable {
    let requestBuilder: RequestBuilder

    func makeRequest(
        endpoint: Endpoint,
        body: UploadBody,
        additionalHeaders: [String: String] = [:]
    ) throws -> HTTPRequest {
        switch body {
        case let .data(data, contentType):
            return try requestBuilder.makeRequest(
                endpoint: endpoint,
                body: data,
                additionalHeaders: additionalHeaders.merging(
                    ["Content-Type": contentType]
                ) { _, new in new }
            )
        case let .file(url, contentType):
            let data = try Data(contentsOf: url)
            return try requestBuilder.makeRequest(
                endpoint: endpoint,
                body: data,
                additionalHeaders: additionalHeaders.merging(
                    ["Content-Type": contentType]
                ) { _, new in new }
            )
        case let .multipart(form):
            let encoded = form.encode()
            return try requestBuilder.makeRequest(
                endpoint: endpoint,
                body: encoded.data,
                additionalHeaders: additionalHeaders.merging(
                    ["Content-Type": encoded.contentType]
                ) { _, new in new }
            )
        }
    }
}
