import Foundation

/// Shared BFF JSON handling for platform update routes (camelCase payloads).
enum PlatformUpdatesBFFClient {
    private struct ErrorPayload: Decodable {
        var error: String?
    }

    static func decodeSuccess<T: Decodable>(
        _ type: T.Type,
        transport: SupabaseTransport,
        response: HTTPResponse
    ) throws -> T {
        guard (200 ... 299).contains(response.statusCode) else {
            throw bffFailure(from: response)
        }
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            throw AppError.unknown(message: "Platform updates response was malformed.")
        }
    }

    static func bffFailure(from response: HTTPResponse) -> AppError {
        if response.statusCode == 401 {
            return AppError.authentication(.sessionExpired)
        }
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: response.data),
           let message = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return AppError.unknown(message: message)
        }
        if response.statusCode == 404 {
            return AppError.unknown(
                message: "Platform updates API is not available (HTTP 404). Deploy the latest web app to Vercel."
            )
        }
        let prefix = response.data.prefix(64)
        if prefix.starts(with: Data("<!DOCTYPE".utf8)) || prefix.starts(with: Data("<html".utf8)) {
            return AppError.unknown(
                message: "Platform updates API returned HTML instead of JSON (HTTP \(response.statusCode)). Deploy the latest web app to Vercel."
            )
        }
        return AppError.unknown(message: "Platform updates request failed (HTTP \(response.statusCode)).")
    }
}
