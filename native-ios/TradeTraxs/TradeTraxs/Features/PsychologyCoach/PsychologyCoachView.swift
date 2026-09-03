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
    private(set) var messages: [PsychologyCoachAIMessage] = []
    private(set) var aiReply: String?

    private let ai: any AIRepository
    private let facts: PsychologyCoachFacts

    init(facts: PsychologyCoachFacts, ai: any AIRepository) {
        self.facts = facts
        self.ai = ai
    }

    var deterministicFallback: String {
        PsychologyCoachDeterministicCoach.buildSummary(from: facts).overview
    }

    func loadInitialExplanation(forceRefresh: Bool = false) async {
        if !forceRefresh,
           let cached = PsychologyCoachSessionStore.shared.cachedAIExplanation,
           PsychologyCoachSessionStore.shared.cachedAIHash == facts.factsHash {
            aiReply = cached
            phase = .ready
            return
        }

        phase = .loading
        do {
            let response = try await ai.explainPsychologyCoach(
                PsychologyCoachAIRequest(
                    facts: facts,
                    messages: [],
                    mode: .explain
                )
            )
            aiReply = response.reply
            PsychologyCoachSessionStore.shared.applyCachedAI(
                explanation: response.reply,
                factsHash: facts.factsHash
            )
            phase = .ready
        } catch {
            aiReply = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func sendFollowUp(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(PsychologyCoachAIMessage(role: "user", content: trimmed))
        phase = .loading

        do {
            let response = try await ai.explainPsychologyCoach(
                PsychologyCoachAIRequest(
                    facts: facts,
                    messages: messages,
                    mode: .followUp
                )
            )
            messages.append(PsychologyCoachAIMessage(role: "assistant", content: response.reply))
            aiReply = response.reply
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct PsychologyCoachView: View {
    @State private var viewModel: PsychologyCoachViewModel
    @State private var questionText = ""

    @Environment(\.themeColors) private var colors

    init(facts: PsychologyCoachFacts, ai: any AIRepository) {
        _viewModel = State(initialValue: PsychologyCoachViewModel(facts: facts, ai: ai))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    Text("Your patterns are computed from your journal. The coach explains them — it never invents statistics.")
                        .experienceStyle(.footnote, color: colors.tertiaryText)

                    contentBlock
                    ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                        if message.role == "assistant" {
                            coachBubble(message.content)
                        } else {
                            userBubble(message.content)
                        }
                    }
                }
                .padding(ExperienceSpacing.md)
            }

            composer
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Psychology Coach")
        .task { await viewModel.loadInitialExplanation() }
        .accessibilityIdentifier("psychologyCoach.view")
    }

    @ViewBuilder
    private var contentBlock: some View {
        switch viewModel.phase {
        case .loading where viewModel.aiReply == nil && viewModel.messages.isEmpty:
            ProgressView("Loading coach…")
        case .failed:
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("Coach unavailable")
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(viewModel.deterministicFallback)
                    .experienceStyle(.body, color: colors.secondaryText)
            }
            .padding(ExperienceSpacing.md)
            .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        default:
            if let reply = viewModel.aiReply, viewModel.messages.isEmpty {
                coachBubble(reply)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            TextField("Ask about your patterns…", text: $questionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 3)
            Button("Ask") {
                let question = questionText
                questionText = ""
                Task { await viewModel.sendFollowUp(question) }
            }
            .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.phase == .loading)
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary)
    }

    private func coachBubble(_ text: String) -> some View {
        Text(text)
            .experienceStyle(.body, color: colors.primaryText)
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .experienceStyle(.body, color: colors.primaryText)
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }
}
