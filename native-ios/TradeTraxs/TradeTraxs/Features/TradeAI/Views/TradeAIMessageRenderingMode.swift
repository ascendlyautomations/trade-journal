import Foundation

/// How assistant replies are laid out in the UI.
enum TradeAIMessageRenderingMode: Hashable, Sendable {
    /// Preset coach sections when a ## Verdict block is present; otherwise Markdown.
    case automatic
    /// Always render stored Markdown (General Trade AI threads).
    case preferMarkdown
}