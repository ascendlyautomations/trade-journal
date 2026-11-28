import SwiftUI

@MainActor
@Observable
final class GeneralTradeAICoachViewModel {
    private(set) var messages: [TradeAIMessage] = []
    private(set) var isLoading = false
    private(set) var isLoadingHistory = false
    private(set) var errorMessage: String?
    private(set) var persistErrorMessage: String?
    private(set) var conversations: [TradeAIConversationInboxItem] = []
    private(set) var conversationID: AIConversationID?
    private(set) var conversationTitle = "General Trade AI"

    var draft = ""
    var pendingAttachmentData: Data?
    var pendingAttachmentMime = "image/jpeg"
    var showsNewConversationSheet = false
    var newConversationTitle = ""
    var showsConversationSwitcher = false
    var showsAllConversationsPage = false
    var showsRenameSheet = false
    var renameDraft = ""
    var renameTargetID: AIConversationID?
    var renameErrorMessage: String?
    var showsTradePicker = false
    var isLoadingTradePicker = false
    var tradePickerTrades: [Trade] = []
    var pendingSharedTrade: Trade?

    var scopeController = TradingRulesAnalyticsScopeController()

    private let ai: any AIRepository
    private let trades: any TradeRepository
    private let detailCache: DetailPresentationCache
    private var accounts: [TradingAccount] = []
    private var profileID: ProfileID?
    private var attachedTradesByID: [TradeID: Trade] = [:]
    private var pendingPersistTurn: (user: TradeAIMessage, assistant: TradeAIMessage)?

    init(ai: any AIRepository, trades: any TradeRepository, detailCache: DetailPresentationCache) {
        self.ai = ai
        self.trades = trades
        self.detailCache = detailCache
    }

    func tradeForAttachment(_ id: TradeID) -> Trade? {
        attachedTradesByID[id]
            ?? detailCache.trade(id: id)
            ?? tradePickerTrades.first(where: { $0.id == id })
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker, let profileID else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        do {
            let page = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            tradePickerTrades = page.items
        } catch {
            tradePickerTrades = []
        }
    }

    func stageTrade(_ trade: Trade) {
        pendingSharedTrade = trade
        attachedTradesByID[trade.id] = trade
        detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
        showsTradePicker = false
    }

    func bootstrap(initialConversationID: AIConversationID?) async {
        defer { GeneralTradeCoachSessionStore.shared.clearReopenConversation() }

        guard let profileID = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) }) else {
            return
        }
        self.profileID = profileID
        accounts = detailCache.accounts(for: profileID) ?? []
        scopeController.hydrate(profileID: profileID, accounts: accounts)
        await refreshConversationList()

        let target =
            initialConversationID
            ?? GeneralTradeCoachSessionStore.shared.pendingReopenConversationID

        if let target {
            await selectConversation(target)
        } else if let recent = conversations.first {
            await selectConversation(recent.id)
        }
    }

    var sortedGeneralConversations: [TradeAIConversationInboxItem] {
        conversations.sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    var dropdownConversations: [TradeAIConversationInboxItem] {
        Array(sortedGeneralConversations.prefix(6))
    }

    var hasMoreConversationsThanDropdown: Bool {
        sortedGeneralConversations.count > 6
    }

    func refreshConversationList() async {
        do {
            let inbox = try await ai.loadConversationInbox(limit: 100)
            conversations = inbox
                .filter { $0.kind == "general_trade" }
                .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
        } catch {
            conversations = []
        }
    }

    func presentRename(for item: TradeAIConversationInboxItem) {
        showsConversationSwitcher = false
        renameTargetID = item.id
        renameDraft = item.title ?? ""
        renameErrorMessage = nil
        showsRenameSheet = true
    }

    func submitRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let target = renameTargetID else {
            renameErrorMessage = "Enter a conversation name."
            return
        }
        renameErrorMessage = nil
        do {
            try await ai.renameAICoachConversation(id: target, title: trimmed)
            showsRenameSheet = false
            renameTargetID = nil
            if conversationID == target {
                conversationTitle = trimmed
            }
            if let index = conversations.firstIndex(where: { $0.id == target }) {
                var row = conversations[index]
                row.title = trimmed
                conversations[index] = row
            }
            await refreshConversationList()
        } catch {
            renameErrorMessage = UserFacingError.message(for: error)
        }
    }

    func selectConversation(_ id: AIConversationID) async {
        conversationID = id
        if let row = conversations.first(where: { $0.id == id }) {
            conversationTitle = row.title ?? "General Trade AI"
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let loaded = try await ai.loadConversationMessages(conversationID: id)
            messages = loaded.1.sorted { $0.createdAt < $1.createdAt }
            await hydrateAttachedTradesFromMessages()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func createConversation() async {
        let title = newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let scope = TradeAIPortfolioScopeMapper.map(scopeController.clientScopeFilter(), accounts: accounts)
        isLoading = true
        defer { isLoading = false }
        do {
            let created = try await ai.createGeneralTradeConversation(
                TradeAICreateConversationRequest(title: title, scope: scope)
            )
            conversationID = created.conversationID
            conversationTitle = title
            messages = []
            showsNewConversationSheet = false
            newConversationTitle = ""
            await refreshConversationList()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    var showsConversationStarters: Bool {
        messages.isEmpty && !isLoading && !isLoadingHistory
    }

    func submitSuggestedQuestion(_ question: String) async {
        await sendMessage(question)
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        await sendMessage(text)
    }

    private func sendMessage(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if Self.isPremiumRestricted {
            ProUpgradeCoordinator.shared.present(reason: .feature(.aiAnalyst))
            return
        }

        errorMessage = nil
        persistErrorMessage = nil
        pendingPersistTurn = nil

        var attachments: [TradeAIAttachment] = []
        if let trade = pendingSharedTrade {
            pendingSharedTrade = nil
            attachments.append(.attachedTrade(trade.id))
            attachedTradesByID[trade.id] = trade
        }
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

        let user = TradeAIMessage(
            role: .user,
            content: text,
            promptKey: "custom",
            attachments: attachments
        )
        messages.append(user)
        isLoading = true
        defer { isLoading = false }

        let scope = TradeAIPortfolioScopeMapper.map(scopeController.clientScopeFilter(), accounts: accounts)
        let apiMessages = GeneralTradeAIAPIMessageBuilder.messagesForAPI(from: messages)

        do {
            let turn = try await ai.analyzePortfolioTurn(
                TradeAIPortfolioTurnRequest(
                    conversationID: conversationID,
                    scope: scope,
                    title: conversationTitle,
                    userMessage: user,
                    apiMessages: apiMessages
                )
            )
            guard turn.analysisSucceeded else {
                if messages.last?.id == user.id {
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
                pendingPersistTurn = (user, assistant)
                persistErrorMessage =
                    "Analysis is on screen, but saving to your account failed. Tap Retry Save."
            }
            await refreshConversationList()
        } catch is ThirdPartyAIConsentError {
            if messages.last?.id == user.id {
                messages.removeLast()
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func retryPersistIfNeeded() async {
        guard let pending = pendingPersistTurn, let conversationID else { return }
        persistErrorMessage = nil
        do {
            try await ai.persistTurn(
                TradeAIPersistTurnRequest(
                    conversationID: conversationID,
                    userMessage: pending.user,
                    assistantMessage: pending.assistant
                )
            )
            pendingPersistTurn = nil
        } catch {
            persistErrorMessage =
                "Analysis is on screen, but saving to your account failed. Tap Retry Save."
        }
    }

    private func hydrateAttachedTradesFromMessages() async {
        let ids = Set(messages.flatMap { $0.attachments.compactMap(\.tradeID) })
        guard !ids.isEmpty, profileID != nil else { return }
        for id in ids where attachedTradesByID[id] == nil {
            if let cached = detailCache.trade(id: id) {
                attachedTradesByID[id] = cached
                continue
            }
            if let loaded = try? await trades.trade(id: id) {
                attachedTradesByID[id] = loaded
                detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: loaded))
            }
        }
    }

    private static var isPremiumRestricted: Bool {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        return ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }
}

struct GeneralTradeAICoachView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    var initialConversationID: AIConversationID?

    @State private var viewModel: GeneralTradeAICoachViewModel
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        initialConversationID: AIConversationID? = nil
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.initialConversationID = initialConversationID
        _viewModel = State(
            initialValue: GeneralTradeAICoachViewModel(
                ai: data.ai,
                trades: data.trades,
                detailCache: data.detailCache
            )
        )
    }

    var body: some View {
        GeneralTradeAIConversationView(
            viewModel: viewModel,
            imagePipeline: data.imagePipeline,
            navigationCoordinator: navigationCoordinator
        )
        .navigationBarTitleDisplayMode(.inline)
        .experienceChevronOnlyBackNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    ExperienceHaptics.play(.selection)
                    viewModel.showsConversationSwitcher = true
                } label: {
                    HStack(spacing: ExperienceSpacing.xxs) {
                        Text(viewModel.conversationTitle)
                            .font(.headline)
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colors.secondaryText)
                    }
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Switch conversation")
            }
        }
        .navigationDestination(isPresented: $viewModel.showsAllConversationsPage) {
            GeneralTradeAIConversationsListView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showsConversationSwitcher) {
            GeneralTradeAIConversationSwitcherSheet(
                viewModel: viewModel,
                onSeeMore: { viewModel.showsAllConversationsPage = true }
            )
        }
        .sheet(isPresented: $viewModel.showsNewConversationSheet) {
            AICoachNewConversationSheet(
                scopeDescription: "Scope uses the account and date filters above.",
                title: $viewModel.newConversationTitle,
                isCreateDisabled: viewModel.newConversationTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isLoading,
                onCancel: { viewModel.showsNewConversationSheet = false },
                onCreate: { Task { await viewModel.createConversation() } }
            )
        }
        .sheet(isPresented: $viewModel.showsRenameSheet) {
            AICoachRenameConversationSheet(
                title: $viewModel.renameDraft,
                isSaveDisabled: viewModel.renameDraft
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: {
                    viewModel.showsRenameSheet = false
                    viewModel.renameTargetID = nil
                    viewModel.renameErrorMessage = nil
                },
                onSave: { Task { await viewModel.submitRename() } }
            )
        }
        .sheet(isPresented: $viewModel.scopeController.showsTimePeriodSheet) {
            TradingRulesAnalyticsTimePeriodSheet(scope: viewModel.scopeController)
        }
        .sheet(isPresented: $viewModel.scopeController.showsFiltersSheet) {
            TradingRulesAnalyticsFiltersSheet(scope: viewModel.scopeController)
                .onAppear { viewModel.scopeController.prepareDraftScopeFilters() }
        }
        .sheet(isPresented: $viewModel.showsTradePicker) {
            TradeSharePickerSheet(
                trades: viewModel.tradePickerTrades,
                imagePipeline: data.imagePipeline,
                isLoading: viewModel.isLoadingTradePicker,
                title: "Attach Trade",
                onSelect: { viewModel.stageTrade($0) },
                onClose: { viewModel.showsTradePicker = false }
            )
            .task { await viewModel.loadTradePickerIfNeeded() }
        }
        .task {
            await viewModel.bootstrap(initialConversationID: initialConversationID)
        }
    }

}