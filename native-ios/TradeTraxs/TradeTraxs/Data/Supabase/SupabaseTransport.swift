import Foundation

/// Shared HTTP surface for Auth / REST / RPC / Storage / Edge Functions.
///
/// Uses the existing Networking foundation — Features never call this type.
nonisolated struct SupabaseTransport: Sendable {
    let client: NetworkClientBox
    let requestBuilder: RequestBuilder
    let configuration: AppConfiguration
    let decoder: JSONResponseDecoder

    init(
        client: NetworkClientBox,
        requestBuilder: RequestBuilder,
        configuration: AppConfiguration
    ) {
        self.client = client
        self.requestBuilder = requestBuilder
        self.configuration = configuration
        let json = JSONDecoder()
        json.keyDecodingStrategy = .useDefaultKeys
        json.dateDecodingStrategy = .deferredToDate
        self.decoder = JSONResponseDecoder(decoder: json)
    }

    var isConfigured: Bool { configuration.isSupabaseConfigured }

    func requireConfigured() throws {
        guard isConfigured else {
            throw AppError.authentication(.notConfigured)
        }
    }

    func send(
        host: APIHost,
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuthentication: Bool = true
    ) async throws -> HTTPResponse {
        try requireConfigured()
        let endpoint = Endpoint(
            host: host,
            path: path,
            method: method,
            queryItems: queryItems,
            headers: headers,
            requiresAuthentication: requiresAuthentication
        )
        let request = try requestBuilder.makeRequest(endpoint: endpoint, body: body)
        do {
            let response = try await client.send(request)
            #if DEBUG
            if host == .supabase {
                SupabaseSessionUsage.recordREST(
                    path: path,
                    method: method.rawValue,
                    bytes: response.data.count
                )
            }
            #endif
            return response
        } catch {
            throw SupabaseErrorMapping.mapNetwork(error)
        }
    }

    func sendDecodable<T: Decodable>(
        _ type: T.Type,
        host: APIHost,
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuthentication: Bool = true
    ) async throws -> T {
        let response = try await send(
            host: host,
            path: path,
            method: method,
            queryItems: queryItems,
            headers: headers,
            body: body,
            requiresAuthentication: requiresAuthentication
        )
        do {
            return try decoder.decode(type, from: response)
        } catch {
            throw AppError.unknown(message: "Failed to decode Supabase response")
        }
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw AppError.unknown(message: "Failed to encode Supabase request")
        }
    }
}
