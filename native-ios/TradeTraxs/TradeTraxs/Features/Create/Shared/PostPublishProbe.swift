import Foundation
import UIKit

#if DEBUG
/// DEBUG-only publish tracing for Posts / Trades / Achievements image flows.
nonisolated enum PostPublishProbe {
    enum Stage: String {
        case validation
        case imageEncode = "imageEncode"
        case upload = "storageUpload"
        case databaseInsert = "createPost"
        case responseDecode = "responseDecode"
        case unknown
    }

    static func log(_ message: String) {
        print("[PostPublish] \(message)")
    }

    static func logStarted(
        flow: String,
        captionLength: Int,
        imagePresent: Bool,
        imageBytes: Int?,
        imagePixelSize: CGSize?,
        cropMetadata: ContentImagePresentation?
    ) {
        log("START flow=\(flow)")
        log("captionLength=\(captionLength)")
        log("hasImage=\(imagePresent)")
        log("imageBytes=\(imageBytes.map(String.init) ?? "nil")")
        if let imagePixelSize {
            log(
                "pixelSize=\(Int(imagePixelSize.width))x\(Int(imagePixelSize.height))"
            )
        } else {
            log("pixelSize=nil")
        }
        if let cropMetadata {
            let crop = cropMetadata.normalizedCrop.map {
                String(
                    format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                    $0.x, $0.y, $0.width, $0.height
                )
            } ?? "nil"
            log(
                "cropMetadata aspect=\(String(format: "%.4f", cropMetadata.presentationAspectRatio)) "
                    + "crop=\(crop) mode=\(cropMetadata.aspectMode.rawValue)"
            )
        } else {
            log("cropMetadata=nil")
        }
    }

    static func logImageEncode(byteCount: Int, mimeType: String, pixelSize: CGSize?) {
        log("stage=imageEncode")
        log("encodedBytes=\(byteCount)")
        log("mimeType=\(mimeType)")
        if let pixelSize {
            log("pixelSize=\(Int(pixelSize.width))x\(Int(pixelSize.height))")
        }
    }

    static func logUploadStarted(storagePath: String, bucket: String) {
        log("stage=storageUpload")
        log("storagePath=\(storagePath)")
        log("bucket=\(bucket)")
    }

    static func logUploadSucceeded(path: String) {
        log("storageUpload SUCCESS path=\(path)")
    }

    static func logDatabaseInsertStarted(table: String, payloadKeys: [String]) {
        log("stage=createPost")
        log("databaseInsertStarted table=\(table)")
        log("payloadKeys=\(payloadKeys.sorted().joined(separator: ","))")
    }

    static func logDatabaseInsertSucceeded(table: String) {
        log("createPost SUCCESS table=\(table)")
    }

    static func logResponseDecodeStarted(table: String) {
        log("stage=responseDecode table=\(table)")
    }

    static func logResponseDecodeSucceeded(table: String) {
        log("responseDecode SUCCESS table=\(table)")
    }

    static func logFailed(stage: Stage, error: Error) {
        log("FAILED")
        log("stage=\(stage.rawValue)")
        log("errorType=\(String(reflecting: type(of: error)))")
        log("localizedDescription=\(error.localizedDescription)")
        log("rawError=\(String(describing: error))")
        log("underlyingError=\(underlyingDescription(error))")
        let postgrest = postgrestDetail(from: error)
        if let code = postgrest.code { log("code=\(code)") }
        if let message = postgrest.message { log("message=\(message)") }
        if let details = postgrest.details { log("details=\(details)") }
        if let hint = postgrest.hint { log("hint=\(hint)") }
        if let status = postgrest.httpStatus { log("statusCode=\(status)") }
    }

    static func logNote(_ message: String) {
        log("note=\(message)")
    }

    static func userFacingMessage(for stage: Stage, error: Error) -> String {
        switch stage {
        case .validation, .imageEncode:
            return "Couldn't prepare image for upload."
        case .upload:
            return "Couldn't upload the image. Please try again."
        case .databaseInsert, .responseDecode, .unknown:
            if isConnectivityError(error) {
                return "Couldn't publish post. Check your connection and try again."
            }
            return "Couldn't publish post. Please try again."
        }
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        if let network = error as? NetworkError {
            switch network {
            case .connectivity, .timeout:
                return true
            default:
                return false
            }
        }
        if let app = error as? AppError, case .transport(let transport) = app {
            switch transport {
            case .connectivity, .timeout:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func underlyingDescription(_ error: Error) -> String {
        var parts: [String] = []
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 6 {
            parts.append("\(type(of: err)): \(err.localizedDescription)")
            current = (err as NSError).userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return parts.joined(separator: " → ")
    }

    private static func postgrestDetail(from error: Error) -> PostgRESTValidationDetail {
        if let network = extractNetworkError(error) {
            switch network {
            case .server(let code, let message):
                return PostgRESTValidationDetail.parse(httpStatus: code, body: message ?? "")
            case .validation(let code, let message):
                return PostgRESTValidationDetail.parse(httpStatus: code, body: message)
            default:
                break
            }
        }
        return PostgRESTValidationDetail.parse(httpStatus: nil, body: String(describing: error))
    }

    private static func extractNetworkError(_ error: Error) -> NetworkError? {
        if let network = error as? NetworkError { return network }
        if let app = error as? AppError, case .transport(let transport) = app {
            return transport
        }
        return nil
    }
}
#else
nonisolated enum PostPublishProbe {
    enum Stage: String {
        case validation
        case imageEncode = "imageEncode"
        case upload = "storageUpload"
        case databaseInsert = "createPost"
        case responseDecode = "responseDecode"
        case unknown
    }

    static func log(_ message: String) {}
    static func logStarted(
        flow: String,
        captionLength: Int,
        imagePresent: Bool,
        imageBytes: Int?,
        imagePixelSize: CGSize?,
        cropMetadata: ContentImagePresentation?
    ) {}
    static func logImageEncode(byteCount: Int, mimeType: String, pixelSize: CGSize?) {}
    static func logUploadStarted(storagePath: String, bucket: String) {}
    static func logUploadSucceeded(path: String) {}
    static func logDatabaseInsertStarted(table: String, payloadKeys: [String]) {}
    static func logDatabaseInsertSucceeded(table: String) {}
    static func logResponseDecodeStarted(table: String) {}
    static func logResponseDecodeSucceeded(table: String) {}
    static func logFailed(stage: Stage, error: Error) {}
    static func logNote(_ message: String) {}

    static func userFacingMessage(for stage: Stage, error: Error) -> String {
        switch stage {
        case .validation, .imageEncode:
            return "Couldn't prepare image for upload."
        case .upload:
            return "Couldn't upload the image. Please try again."
        case .databaseInsert, .responseDecode, .unknown:
            return "Couldn't publish post. Please try again."
        }
    }
}
#endif
