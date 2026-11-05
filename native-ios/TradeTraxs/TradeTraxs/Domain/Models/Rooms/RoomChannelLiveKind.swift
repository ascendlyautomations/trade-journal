import Foundation

/// Web `room_sections.live_kind`.
enum RoomChannelLiveKind: String, Codable, Sendable, Hashable {
    case text
    case voiceOpen = "voice_open"
    case voiceStage = "voice_stage"

    init(rawDatabaseValue: String?) {
        let normalized = (rawDatabaseValue ?? "text").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case Self.voiceOpen.rawValue:
            self = .voiceOpen
        case Self.voiceStage.rawValue:
            self = .voiceStage
        default:
            self = .text
        }
    }

    var supportsLiveVoice: Bool {
        switch self {
        case .voiceOpen, .voiceStage:
            return true
        case .text:
            return false
        }
    }
}
