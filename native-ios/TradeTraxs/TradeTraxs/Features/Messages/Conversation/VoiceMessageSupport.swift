import CoreGraphics
import Foundation

enum VoiceMessageSupport {
    /// Maximum recording length — matches common DM voice message limits.
    static let maxRecordingDuration: TimeInterval = 120

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    static func waveformHeights(seed: String, count: Int = 24) -> [CGFloat] {
        var values: [CGFloat] = []
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        for index in 0..<count {
            hash = hash &* 1_103_515_245 &+ UInt64(index)
            let normalized = CGFloat(hash % 100) / 100
            values.append(0.25 + normalized * 0.75)
        }
        return values
    }
}
