import Foundation

/// Decodes response bodies into typed models.
nonisolated protocol ResponseDecoding: Sendable {
    func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T
}

nonisolated struct JSONResponseDecoder: ResponseDecoding {
    let decoder: JSONDecoder
    private let errorMapper = NetworkErrorMapper()

    init(decoder: JSONDecoder = JSONResponseDecoder.makeDefaultDecoder()) {
        self.decoder = decoder
    }

    func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw errorMapper.mapDecoding(error)
        }
    }

    static func makeDefaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
