import AppIntents
import Foundation

/// Bridges Live Activity controls into the main app (`RoomLiveVoiceCoordinator`).
public enum LiveVoiceActivityIntentBridge: Sendable {
    public static var toggleMute: (@Sendable () async -> Void)?
    public static var toggleHand: (@Sendable () async -> Void)?
    public static var leaveVoice: (@Sendable () async -> Void)?
}

@available(iOS 17.0, *)
public struct LiveVoiceToggleMuteIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle mute"
    public static var description = IntentDescription("Mute or unmute your microphone in General Voice.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveVoiceActivityIntentBridge.toggleMute?()
        return .result()
    }
}

@available(iOS 17.0, *)
public struct LiveVoiceToggleHandIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle raise hand"
    public static var description = IntentDescription("Raise or lower your hand in General Voice.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveVoiceActivityIntentBridge.toggleHand?()
        return .result()
    }
}

@available(iOS 17.0, *)
public struct LiveVoiceLeaveIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Leave voice"
    public static var description = IntentDescription("Disconnect from General Voice.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveVoiceActivityIntentBridge.leaveVoice?()
        return .result()
    }
}
