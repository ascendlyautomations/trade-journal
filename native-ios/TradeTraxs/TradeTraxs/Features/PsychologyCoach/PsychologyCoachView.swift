import SwiftUI

@MainActor
@Observable
final class PsychologyCoachViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var messages: [AICoachConversationMessage] = []
    private(set) var conversationID: AIConversationID?
    private(set) var facts: PsychologyCoachFacts
    private(set) var bootstrapGeneration = 0

    private let ai: any AIRepository
    private var bootstrapInFlight = false

    init(facts: PsychologyCoachFacts, ai: any AIRepository) {
        self.facts = facts
        self.ai = ai
    }

    var deterministicFallback: String {
        facts.deterministicCoach.overview
    }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    func startNewConversation() async {
        PsychologyCoachSessionStore.shared.clearReopenConversation()
        conversationID = nil
        messages = []
        bootstrapGeneration += 1
        await bootstrap(forceRefresh: true)
    }

    func bootstrap(forceRefresh: Bool = false) async {
        if bootstrapInFlight {
            PsychologyCoachTrace.bootstrapSkipped(reason: "in_flight")
            return
        }
        bootstrapInFlight = true
        defer { bootstrapInFlight = false }

        if TraxsProPreviewSession.shared.activePreviewEnvironment != nil
            || ExploreModeSupport.isActive
        {
            messages = [
                AICoachConversationMessage(role: .assistant, content: deterministicFallback, promptKey: "preview")
            ]
            phase = .ready
            return
        }

        phase = .loading
        defer { PsychologyCoachSessionStore.shared.clearReopenConversation() }

        do {
            if let reopen = PsychologyCoachSessionStore.shared.pendingReopenConversationID {
                conversationID = reopen
                let loaded = try await ai.loadConversationMessages(conversationID: reopen)
                if let snapshot = loaded.0.psychologyFactsSnapshot {
                    facts = snapshot
                }
                messages = loaded.1.map(Self.mapTradeAIMessage)
                phase = .ready
                return
            }

            if !forceRefresh,
               let cached = PsychologyCoachSessionStore.shared.cachedAIExplanation,
               PsychologyCoachSessionStore.shared.cachedAIHash == facts.factsHash,
               conversationID == nil
            {
                let assistantId = UUID().uuidString
                let response = try await ai.explainPsychologyCoach(
                    PsychologyCoachAIRequest(
                        facts: facts,
                        messages: [],
                        mode: .explain,
                        conversationID: nil,
                        createConversation: true,
                        assistantMessageID: assistantId,
                        persistCachedOnly: true,
                        cachedReply: cached
                    )
                )
                if let id = response.conversationID {
                    conversationID = id
                }
                let assistant = AICoachConversationMessage(
                    id: UUID(uuidString: response.assistantMessageID ?? assistantId) ?? UUID(),
                    role: .assistant,
                    content: cached,
                    promptKey: "explain"
                )
                messages = [assistant]
                phase = .ready
                return
            }

            let response = try await ai.explainPsychologyCoach(
                PsychologyCoachAIRequest(
                    facts: facts,
                    messages: [],
                    mode: .explain,
                    conversationID: conversationID,
                    createConversation: conversationID == nil
                )
            )
            if let id = response.conversationID {
                conversationID = id
            }
            let assistant = AICoachConversationMessage(
                id: UUID(uuidString: response.assistantMessageID ?? "") ?? UUID(),
                role: .assistant,
                content: response.reply,
                promptKey: "explain"
            )
            messages = [assistant]
            PsychologyCoachSessionStore.shared.applyCachedAI(
                explanation: response.reply,
                factsHash: facts.factsHash
            )
            phase = .ready
        } catch is ThirdPartyAIConsentError {
            messages = []
            phase = .idle
        } catch {
            PsychologyCoachTrace.bootstrapFailed(
                category: String(describing: type(of: error)).prefix(40).description
            )
            phase = .failed(Self.userFacingCoachError(error))
        }
    }

    private static func userFacingCoachError(_ error: Error) -> String {
        let message = UserFacingError.message(for: error)
        if message.isEmpty || message.lowercased().contains("cancelled") {
            return "The coach request did not finish. Pull to refresh or tap Try again."
        }
        return message
    }

    func sendFollowUp(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if TraxsProPreviewSession.shared.activePreviewEnvironment != nil || ExploreModeSupport.isActive {
            let user = AICoachConversationMessage(role: .user, content: trimmed)
            let assistant = AICoachConversationMessage(role: .assistant, content: deterministicFallback, promptKey: "preview")
            messages.append(contentsOf: [user, assistant])
            phase = .ready
            return
        }

        let user = AICoachConversationMessage(role: .user, content: trimmed)
        messages.append(user)
        phase = .loading

        do {
            let apiMessages = messages.map {
                PsychologyCoachAIMessage(role: $0.role.rawValue, content: $0.content)
            }
            let response = try await ai.explainPsychologyCoach(
                PsychologyCoachAIRequest(
                    facts: facts,
                    messages: apiMessages,
                    mode: .followUp,
                    conversationID: conversationID,
                    createConversation: false,
                    assistantMessageID: UUID().uuidString,
                    userMessage: PsychologyCoachAITurnUserMessage(
                        id: user.id.uuidString,
                        displayContent: trimmed,
                        createdAt: ISO8601.string(from: user.createdAt ?? Date())
                    )
                )
            )
            if let id = response.conversationID {
                conversationID = id
            }
            let assistant = AICoachConversationMessage(
                id: UUID(uuidString: response.assistantMessageID ?? "") ?? UUID(),
                role: .assistant,
                content: response.reply,
                promptKey: "followUp"
            )
            messages.append(assistant)
            phase = .ready
        } catch is ThirdPartyAIConsentError {
            if messages.last?.role == .user, messages.last?.content == trimmed {
                messages.removeLast()
            }
            phase = .ready
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private static func mapTradeAIMessage(_ message: TradeAIMessage) -> AICoachConversationMessage {
        let role: AICoachConversationRole =
            message.role == .assistant ? .assistant : .user
        return AICoachConversationMessage(
            id: UUID(uuidString: message.id) ?? UUID(),
            role: role,
            content: message.content,
            promptKey: message.promptKey,
            createdAt: message.createdAt
        )
    }
}

struct PsychologyCoachView: View {
    @State private var viewModel: PsychologyCoachViewModel
    @State private var draft = ""
    @Environment(\.themeColors) private var colors

    init(facts: PsychologyCoachFacts, ai: any AIRepository) {
        _viewModel = State(
            initialValue: PsychologyCoachViewModel(facts: facts, ai: ai)
        )
    }

    var body: some View {
        Group {
            if case .failed(let message) = viewModel.phase, viewModel.messages.isEmpty {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    Text("Coach unavailable")
                        .experienceStyle(.headline)
                    Text(message)
                        .experienceStyle(.body, color: colors.secondaryText)
                    ExperienceButton(title: "Try again", kind: .primary) {
                        Task { await viewModel.bootstrap(forceRefresh: true) }
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                PsychologyCoachConversationView(
                    messages: viewModel.messages,
                    isLoading: viewModel.isLoading,
                    isLoadingBootstrap: viewModel.phase == .loading && viewModel.messages.isEmpty,
                    draft: $draft,
                    onSend: {
                        let text = draft
                        draft = ""
                        Task { await viewModel.sendFollowUp(text) }
                    }
                )
            }
        }
        .aiCoachConversationRootChrome()
        .experienceNavigationTitle("Psychology Coach")
        .experienceChevronOnlyBackNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ExperienceHaptics.play(.selection)
                    Task { await viewModel.startNewConversation() }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .frame(
                            width: ExperienceAccessibility.minTouchTarget,
                            height: ExperienceAccessibility.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("New conversation")
                .accessibilityIdentifier("psychologyCoach.newConversation")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task(id: viewModel.bootstrapGeneration) {
            await viewModel.bootstrap()
        }
        .accessibilityIdentifier("psychologyCoach.view")
    }
}