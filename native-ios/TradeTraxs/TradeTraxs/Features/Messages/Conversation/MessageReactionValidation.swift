import Foundation

/// Unicode emoji validation — web `lib/messageReactionValidation.ts` parity.
nonisolated enum MessageReactionValidation {
    static let quickPickEmojis = MessageReactionSemantics.quickPickEmojis
    static let doubleTapLikeEmoji = MessageReactionSemantics.doubleTapLikeEmoji

    private static let maxCodeUnits = 16
    private static let maxUTF8Bytes = 64

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.precomposedStringWithCanonicalMapping
        guard normalized.count <= maxCodeUnits else { return nil }
        guard normalized.utf8.count <= maxUTF8Bytes else { return nil }
        guard !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        guard hasEmojiPresentation(normalized) else { return nil }
        return normalized
    }

    static func isValid(_ raw: String) -> Bool {
        normalize(raw) != nil
    }

    private static func hasEmojiPresentation(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if isEmojiScalar(scalar) || scalar.value == 0x200D || scalar.value == 0xFE0F {
                return true
            }
        }
        return false
    }

    private static func isEmojiScalar(_ scalar: UnicodeScalar) -> Bool {
        let cp = scalar.value
        if (0x1F000 ... 0x1FAFF).contains(cp) { return true }
        if (0x2600 ... 0x27BF).contains(cp) { return true }
        if (0x2300 ... 0x23FF).contains(cp) { return true }
        if cp == 0x2B50 || cp == 0x2764 { return true }
        if (0x1F3FB ... 0x1F3FF).contains(cp) { return true }
        return false
    }
}