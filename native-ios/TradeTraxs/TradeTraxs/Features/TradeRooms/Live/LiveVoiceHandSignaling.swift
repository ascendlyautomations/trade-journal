import Foundation

enum LiveVoiceHandPayload: Codable, Sendable {
    case handState(identity: String, raised: Bool)

    enum CodingKeys: String, CodingKey {
        case type, identity, raised
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let identity = try c.decode(String.self, forKey: .identity)
        switch type {
        case "hand_state":
            let raised = try c.decode(Bool.self, forKey: .raised)
            self = .handState(identity: identity, raised: raised)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .handState(let identity, let raised):
            try c.encode("hand_state", forKey: .type)
            try c.encode(identity, forKey: .identity)
            try c.encode(raised, forKey: .raised)
        }
    }

    static func encodeHandState(identity: String, raised: Bool) throws -> Data {
        try JSONEncoder().encode(LiveVoiceHandPayload.handState(identity: identity, raised: raised))
    }

    static func decode(from data: Data) -> LiveVoiceHandPayload? {
        try? JSONDecoder().decode(LiveVoiceHandPayload.self, from: data)
    }
}
