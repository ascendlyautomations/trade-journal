import Foundation
import Observation

/// Owns Trade AI conversation for a single Trade Detail presentation.
///
/// Loads persisted history on open; calls the BFF only when the user submits a new prompt.
@Observable
@MainActor
final class TradeAISectionViewModel {
    private(set) var messages: [TradeAIMessage] = []
    private(set) var isAnalyzing = false
    private(set) var isLoadingHistory = false
    private(set) var errorMessage: String?
    /// Selected analysis option for the native Menu → Analyze flow.
    var selectedPrompt: TradeAISuggestedPrompt = TradeAISuggestedPrompts.default
    /// Custom question field (advanced users).
    var draft = ""

    let analysisOptions = TradeAISuggestedPrompts.all

    private let tradeID: TradeID
    private let ai: any AIRepository
    private var context: TradeAIContext?
    private var analyzeTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var didLoadHistory = false

    init(tradeID: TradeID, ai: any AIRepository) {
        self.tradeID = tradeID
        self.ai = ai
    }

    /// Refresh context whenever Trade Detail finishes loading / refreshing the trade.
    func updateContext(trade: Trade?, notes: [TradeNote]) {
        guard let trade, trade.id == tradeID else { return }
        context = TradeAIMapper.makeContext(trade: trade, notes: notes)
    }

    /// Load stored AI turns once. Never regenerates prior replies.
    func loadHistoryIfNeeded() async {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        historyTask?.cancel()
        do {
            let history = try await ai.loadConversation(tradeID: tradeID)
            guard !Task.isCancelled else { return }
            if !history.isEmpty {
                messages = history.sorted { $0.createdAt < $1.createdAt }
            }
        } catch {
            // Soft-fail history — analysis still works offline from empty state.
            guard !Task.isCancelled else { return }
        }
    }

    /// Submit the currently selected analysis option (one tap after Menu selection).
    func analyzeSelected() async {
        guard !isAnalyzing else { return }
        await submit(
            displayText: selectedPrompt.title,
            promptKey: selectedPrompt.id
        )
    }

    /// Primary Analyze action — custom question when filled, otherwise selected preset.
    func analyzeTapped() async {
        let custom = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            draft = ""
            await submit(displayText: custom, promptKey: "custom")
            return
        }
        await analyzeSelected()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        await submit(displayText: text, promptKey: "custom")
    }

    private func submit(displayText: String, promptKey: String) async {
        guard !isAnalyzing else { return }
        guard let context else {
            errorMessage = "Trade is still loading. Try again in a moment."
            return
        }

        ExperienceHaptics.play(.selection)
        errorMessage = nil

        let userMessage = TradeAIMessage(
            role: .user,
            content: displayText,
            promptKey: promptKey
        )
        messages.append(userMessage)

        if let ownerRaw = context.tradePayload.user_id,
           ProfileSectionSupport.isLocalDevelopmentProfile(ProfileID(ownerRaw))
        {
            let assistant = TradeAIMessage(
                role: .assistant,
                content: Self.developmentReply(
                    for: displayText,
                    promptKey: promptKey,
                    ticker: context.tradePayload.ticker
                )
            )
            messages.append(assistant)
            await persistCompletedTurn(user: userMessage, assistant: assistant)
            return
        }

        isAnalyzing = true
        analyzeTask?.cancel()
        analyzeTask = Task {
            defer { isAnalyzing = false }
            do {
                let apiMessages = TradeAIAPIMessageBuilder.messagesForAPI(from: messages)
                let response = try await ai.analyzeTrade(
                    TradeAIAnalyzeRequest(context: context, messages: apiMessages)
                )
                guard !Task.isCancelled else { return }
                let assistant = TradeAIMessage(role: .assistant, content: response.reply)
                messages.append(assistant)
                await persistCompletedTurn(user: userMessage, assistant: assistant)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = Self.userFacingMessage(for: error)
                // Drop the optimistic user turn so reopen doesn't treat a failed ask as history.
                if messages.last?.id == userMessage.id {
                    messages.removeLast()
                }
            }
        }
        await analyzeTask?.value
    }

    private func persistCompletedTurn(user: TradeAIMessage, assistant: TradeAIMessage) async {
        do {
            try await ai.persistMessages([user, assistant], tradeID: tradeID)
        } catch {
            // Analysis already succeeded; persistence is best-effort.
        }
    }

    /// Maps AppError / NetworkError to readable copy (never raw `NetworkError error N`).
    private static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        if let network = error as? NetworkError {
            return UserFacingError.map(network).message
        }
        return "We couldn't complete the analysis. Please try again."
    }

    private static func developmentReply(
        for prompt: String,
        promptKey: String,
        ticker: String?
    ) -> String {
        let symbol = ticker ?? "this trade"
        let focus: String
        switch promptKey {
        case "mistakes":
            focus = "Exit timing drifted from the plan — that was the costly mistake."
        case "execution":
            focus = "Execution 6/10 — entry was fine; management and exit were soft."
        case "risk":
            focus = "Risk was acceptable on paper, but size didn't match the weak RR."
        case "emotional":
            focus = "Early exit looks more like comfort-taking than plan-driven management."
        case "journal":
            focus = "Clean long in \(symbol); result hinged on an early exit vs planned target."
        default:
            focus = "Highest leverage is holding to the planned invalidation / target."
        }

        return """
        ## Verdict
        🟡 Good idea, soft finish on \(symbol).

        ## Biggest Insight
        \(focus) You asked: \(prompt).

        ## Key Improvements
        - Define exit rules before entry and write them in the journal.
        - Size only after RR is clear — not the other way around.
        - Review one similar winner before the next session.

        ## Next Trade Focus
        Pre-commit the exit and do not move it mid-trade without a written reason.
        """
    }
}
