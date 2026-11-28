import Foundation
import Observation

/// Owns Trade AI conversation for a single Trade Detail presentation.
///
/// Loads persisted history on open; calls the BFF only when the user submits a new prompt.
@Observable
@MainActor
final class TradeAISectionViewModel {
    private(set) var messages: [TradeAIMessage] = []
    private(set) var trade: Trade?
    private(set) var isAnalyzing = false
    private(set) var isLoadingHistory = false
    private(set) var errorMessage: String?
    private(set) var persistErrorMessage: String?
    /// Selected analysis option for the native Menu → Analyze flow.
    var selectedPrompt: TradeAISuggestedPrompt = TradeAISuggestedPrompts.default
    /// Custom question field (advanced users).
    var draft = ""
    var pendingAttachmentData: Data?
    var pendingAttachmentMime = "image/jpeg"

    let analysisOptions = TradeAISuggestedPrompts.all

    private let tradeID: TradeID
    private let ai: any AIRepository
    private var context: TradeAIContext?
    private var analyzeTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var didLoadHistory = false
    private var pendingPersistTurn: (user: TradeAIMessage, assistant: TradeAIMessage)?
    private(set) var conversationID: AIConversationID?

    init(tradeID: TradeID, ai: any AIRepository) {
        self.tradeID = tradeID
        self.ai = ai
    }

    /// Refresh context whenever Trade Detail finishes loading / refreshing the trade.
    func noteConversationID(_ id: AIConversationID) {
        conversationID = id
    }

    func updateContext(trade: Trade?, notes: [TradeNote]) {
        guard let trade, trade.id == tradeID else { return }
        self.trade = trade
        context = TradeAIMapper.makeContext(trade: trade, notes: notes)
    }

    var showsConversationStarters: Bool {
        messages.isEmpty && !isAnalyzing && !isLoadingHistory
    }

    func submitPreset(_ prompt: TradeAISuggestedPrompt) async {
        selectedPrompt = prompt
        await submit(displayText: prompt.title, promptKey: prompt.id)
    }

    /// Load stored AI turns once. Never regenerates prior replies.
    func loadHistoryIfNeeded() async {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        historyTask?.cancel()
        do {
            let history: [TradeAIMessage]
            if let conversationID {
                let loaded = try await ai.loadConversationMessages(conversationID: conversationID)
                history = loaded.1
            } else {
                history = try await ai.loadConversation(tradeID: tradeID)
            }
            guard !Task.isCancelled else { return }
            if !history.isEmpty {
                messages = history.sorted { $0.createdAt < $1.createdAt }
            }
        } catch {
            // Soft-fail history, analysis still works offline from empty state.
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

    /// Primary Analyze action, custom question when filled, otherwise selected preset.
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
        if Self.isPremiumAnalysisRestricted {
            ProUpgradeCoordinator.shared.present(reason: .feature(.aiAnalyst))
            return
        }
        guard let context else {
            errorMessage = "Trade is still loading. Try again in a moment."
            return
        }

        ExperienceHaptics.play(.selection)
        errorMessage = nil
        persistErrorMessage = nil
        pendingPersistTurn = nil

        var attachments: [TradeAIAttachment] = []
        if let imageData = pendingAttachmentData {
            pendingAttachmentData = nil
            do {
                let uploaded = try await ai.uploadAICoachAttachment(
                    TradeAIUploadAttachmentRequest(
                        imageData: imageData,
                        mimeType: pendingAttachmentMime,
                        conversationID: conversationID
                    )
                )
                attachments = [uploaded]
            } catch {
                errorMessage = "We couldn't upload that image. Try again."
                return
            }
        }

        let userMessage = TradeAIMessage(
            role: .user,
            content: displayText,
            promptKey: promptKey,
            attachments: attachments
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
                let turn = try await ai.analyzeTradeTurn(
                    TradeAITradeTurnRequest(
                        tradeID: tradeID,
                        conversationID: conversationID,
                        userMessage: userMessage,
                        apiMessages: apiMessages
                    )
                )
                guard !Task.isCancelled else { return }
                if turn.backendCode == "pro_required" {
                    if messages.last?.id == userMessage.id {
                        messages.removeLast()
                    }
                    ProUpgradeCoordinator.shared.present(reason: .feature(.aiAnalyst))
                    return
                }

                guard turn.analysisSucceeded else {
                    if messages.last?.id == userMessage.id {
                        messages.removeLast()
                    }
                    errorMessage = turn.reply
                    return
                }

                conversationID = turn.conversationID
                let assistant = TradeAIMessage(
                    id: turn.assistantMessageID,
                    role: .assistant,
                    content: turn.reply
                )
                messages.append(assistant)
                if turn.shouldPersist {
                    pendingPersistTurn = nil
                    persistErrorMessage = nil
                    #if DEBUG
                    TradeAITrace.persistTurnSkipped(reason: "server_persisted")
                    #endif
                } else if let persistError = turn.persistError, !persistError.isEmpty {
                    pendingPersistTurn = (userMessage, assistant)
                    persistErrorMessage =
                        "Analysis is on screen, but saving to your account failed. Tap Retry Save."
                }
            } catch is ThirdPartyAIConsentError {
                guard !Task.isCancelled else { return }
                if messages.last?.id == userMessage.id {
                    messages.removeLast()
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = Self.userFacingMessage(for: error)
            }
        }
        await analyzeTask?.value
    }

    func retryPersistIfNeeded() async {
        guard let pending = pendingPersistTurn else { return }
        persistErrorMessage = nil
        await persistCompletedTurn(user: pending.user, assistant: pending.assistant)
    }

    private func persistCompletedTurn(user: TradeAIMessage, assistant: TradeAIMessage) async {
        do {
            if let conversationID {
                #if DEBUG
                TradeAITrace.persistenceStarted(rowCount: 2, payloadType: "persist-turn")
                #endif
                try await ai.persistTurn(
                    TradeAIPersistTurnRequest(
                        conversationID: conversationID,
                        userMessage: user,
                        assistantMessage: assistant
                    )
                )
            } else {
                #if DEBUG
                TradeAITrace.persistenceStarted(rowCount: 2, payloadType: "trade_ai_messages")
                #endif
                try await ai.persistMessages([user, assistant], tradeID: tradeID)
            }
            pendingPersistTurn = nil
            persistErrorMessage = nil
        } catch {
            if let feature = ProGateReasonParser.feature(from: error), feature == .aiAnalyst {
                ProUpgradeCoordinator.shared.present(reason: .feature(.aiAnalyst))
                pendingPersistTurn = nil
                persistErrorMessage = nil
                return
            }
            pendingPersistTurn = (user, assistant)
            persistErrorMessage =
                "Analysis is on screen, but saving to your account failed. Tap Retry Save."
        }
    }

    private static var isPremiumAnalysisRestricted: Bool {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        return ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
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
            focus = "Exit timing drifted from plan, that was the highest-leverage fix."
            return """
            ## Biggest Insight
            \(focus) You asked: \(prompt).

            ## Key Improvements
            1. **Define exits first** — Pre-write invalidation and target before entry so management is not improvised.
            2. **Size after RR** — Match contracts to planned stop distance, not how confident you feel after entry.
            3. **Use the chart** — Mark structure on the screenshot and only move stops when that level actually breaks.

            ## Next Trade Focus
            Pre-commit the exit and do not change it mid-trade without a written reason tied to structure.
            """
        case "execution":
            focus = "Execution 6/10, entry was fine; management and exit were soft."
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
        - Size only after RR is clear, not the other way around.
        - Review one similar winner before the next session.

        ## Next Trade Focus
        Pre-commit the exit and do not move it mid-trade without a written reason.
        """
    }
}
