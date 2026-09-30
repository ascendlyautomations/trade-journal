import Foundation

/// Supabase Storage POST with URLSession task `Progress` (real byte fraction).
enum StorageUploadProgressTransport {
    static func upload(
        request: URLRequest,
        body: Data,
        progressJobID: String
    ) async throws -> (Data, URLResponse) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-upload-\(UUID().uuidString).bin")
        try body.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await upload(
            request: request,
            fileURL: tempURL,
            uploadPayloadBytes: body.count,
            progressJobID: progressJobID,
            deleteFileWhenComplete: false
        )
    }

    static func upload(
        request: URLRequest,
        fileURL: URL,
        uploadPayloadBytes: Int,
        progressJobID: String,
        deleteFileWhenComplete: Bool = false
    ) async throws -> (Data, URLResponse) {
        var uploadRequest = request
        uploadRequest.httpBody = nil
        uploadRequest.httpBodyStream = nil

        let requestURL = uploadRequest.url ?? request.url ?? URL(string: "about:blank")!
        let location = StorageUploadDiagnostics.parseObjectLocation(from: requestURL)
            ?? StorageUploadDiagnostics.ObjectLocation(bucket: "unknown", path: requestURL.path)
        StorageUploadDiagnostics.logRequest(
            bucket: location.bucket,
            path: location.path,
            method: uploadRequest.httpMethod ?? "POST",
            request: uploadRequest,
            uploadPayloadBytes: uploadPayloadBytes
        )

        let session = URLSession.shared
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: uploadRequest, fromFile: fileURL) { data, response, error in
                if deleteFileWhenComplete {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                let payload = data ?? Data()
                if let http = response as? HTTPURLResponse {
                    StorageUploadDiagnostics.logResponse(
                        bucket: location.bucket,
                        path: location.path,
                        statusCode: http.statusCode,
                        supabaseCode: nil,
                        responseData: payload
                    )
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (payload, response))
            }
            let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                Task {
                    await UploadProgressRelay.shared.report(
                        jobID: progressJobID,
                        fraction: progress.fractionCompleted
                    )
                }
            }
            objc_setAssociatedObject(
                task,
                &observationKey,
                observation,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            task.resume()
        }
    }
}

private nonisolated(unsafe) var observationKey: UInt8 = 0
