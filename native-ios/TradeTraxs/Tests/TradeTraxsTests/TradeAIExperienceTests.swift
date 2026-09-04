import XCTest
@testable import TradeTraxs

@MainActor
final class TradeAIExperienceTests: XCTestCase {
    func testSuggestedPromptsCoverRequiredIntents() {
        let titles = Set(TradeAISuggestedPrompts.all.map(\.title))
        XCTAssertTrue(titles.contains("Analyze this trade"))
        XCTAssertTrue(titles.contains("Compare to my winning trades"))
        XCTAssertTrue(titles.contains("Compare to my losing trades"))
        XCTAssertTrue(titles.contains("Find my biggest mistakes"))
        XCTAssertTrue(titles.contains("Review my risk management"))
        XCTAssertTrue(titles.contains("Evaluate my execution"))
        XCTAssertTrue(titles.contains("Was this emotional trading?"))
        XCTAssertTrue(titles.contains("Did I follow my trading plan?"))
        XCTAssertTrue(titles.contains("Generate a journal summary"))
        XCTAssertTrue(titles.contains("Give me 3 action items"))
        XCTAssertEqual(TradeAISuggestedPrompts.all.count, 10)
        XCTAssertEqual(TradeAISuggestedPrompts.default.id, "analyze")
    }

    func testEveryPresetHasSpecializedCoachPrompt() {
        for preset in TradeAISuggestedPrompts.all {
            let content = TradeAICoachPrompts.apiContent(for: preset)
            XCTAssertTrue(content.contains("## Verdict"), preset.id)
            XCTAssertTrue(content.contains("100–250"), preset.id)
            XCTAssertTrue(content.contains("SPECIALIZED FOCUS"), preset.id)
            XCTAssertFalse(content.isEmpty, preset.id)
        }

        let custom = TradeAICoachPrompts.apiContentForCustomQuestion("Was my entry early?")
        XCTAssertTrue(custom.contains("Was my entry early?"))
        XCTAssertTrue(custom.contains("250"))
    }

    func testCoachResponseParserExtractsSections() {
        let reply = """
        ## Verdict
        🟢 Strong trade, weak exit.

        ## Biggest Insight
        You left 1R on the table by scaling out early.

        ## Key Improvements
        - Hold to target unless invalidation prints.
        - Size after RR is clear.
        - Journal the exit rule before entry.

        ## Next Trade Focus
        Pre-commit the exit and do not move it mid-trade.
        """
        let sections = TradeAICoachResponseParser.parse(reply)
        XCTAssertEqual(sections?.verdict, "🟢 Strong trade, weak exit.")
        XCTAssertTrue(sections?.biggestInsight?.contains("1R") == true)
        XCTAssertEqual(sections?.keyImprovements.count, 3)
        XCTAssertTrue(sections?.nextTradeFocus?.contains("Pre-commit") == true)
    }

    func testMapperBuildsBFFTradePayload() {
        let trade = makeTrade()
        let context = TradeAIMapper.makeContext(
            trade: trade,
            notes: [
                TradeNote(
                    id: TradeNoteID("n1"),
                    tradeID: trade.id,
                    body: "Held through news",
                    createdAt: trade.createdAt,
                    updatedAt: trade.updatedAt
                ),
            ]
        )
        XCTAssertEqual(context.tradeID, trade.id)
        XCTAssertEqual(context.tradePayload.id, trade.id.rawValue)
        XCTAssertEqual(context.tradePayload.ticker, "MNQ")
        XCTAssertEqual(context.tradePayload.direction, "Long")
        XCTAssertEqual(context.tradePayload.notes, "Held through news")
        XCTAssertEqual(context.journalNotes, ["Held through news"])
        XCTAssertEqual(context.mediaAttachments.first?.kind, .screenshot)
    }

    func testAnalyzeSelectedUsesSpecializedPromptAndPersists() async {
        let trade = makeTrade()
        let repo = MockAIRepository(reply: coachReply)
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])
        vm.selectedPrompt = TradeAISuggestedPrompts.all.first { $0.id == "risk" }!
        await vm.analyzeSelected()

        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertEqual(vm.messages.first?.content, "Review my risk management")
        XCTAssertEqual(vm.messages.first?.promptKey, "risk")
        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertTrue(vm.draft.isEmpty)

        let apiUser = repo.lastRequest?.messages.first { $0.role == .user }
        XCTAssertTrue(apiUser?.content.contains("SPECIALIZED FOCUS") == true)
        XCTAssertTrue(apiUser?.content.contains("risk management") == true)
        XCTAssertEqual(repo.persistedBatches.count, 1)
        XCTAssertEqual(repo.persistedBatches.first?.count, 2)
    }

    func testAnalyzeTappedUsesCustomQuestionWhenFilled() async {
        let trade = makeTrade()
        let repo = MockAIRepository(reply: coachReply)
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])
        vm.draft = "Was my entry early?"
        await vm.analyzeTapped()

        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertEqual(vm.messages.first?.content, "Was my entry early?")
        XCTAssertEqual(vm.messages.first?.promptKey, "custom")
        XCTAssertTrue(vm.draft.isEmpty)
    }

    func testAnalyzeTappedUsesSelectedPresetWhenCustomBlank() async {
        let trade = makeTrade()
        let repo = MockAIRepository(reply: coachReply)
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])
        vm.selectedPrompt = TradeAISuggestedPrompts.all.first { $0.id == "risk" }!
        await vm.analyzeTapped()

        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertEqual(vm.messages.first?.content, "Review my risk management")
        XCTAssertEqual(vm.messages.first?.promptKey, "risk")
    }

    func testCustomQuestionStillSendsWithOpenCoachPrompt() async {
        let trade = makeTrade()
        let repo = MockAIRepository(reply: "**Solid** setup.\n\n1. Hold plan\n2. Size down")
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])
        vm.draft = "Was my entry early?"
        await vm.send()

        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertEqual(vm.messages.first?.content, "Was my entry early?")
        XCTAssertEqual(vm.messages.first?.promptKey, "custom")
        let apiUser = repo.lastRequest?.messages.first { $0.role == .user }
        XCTAssertTrue(apiUser?.content.contains("Was my entry early?") == true)
        XCTAssertTrue(apiUser?.content.contains("trading coach") == true)
    }

    func testLoadHistoryDoesNotRegenerate() async {
        let trade = makeTrade()
        let history = [
            TradeAIMessage(role: .user, content: "Find my biggest mistakes", promptKey: "mistakes"),
            TradeAIMessage(role: .assistant, content: coachReply),
        ]
        let repo = MockAIRepository(reply: "SHOULD NOT CALL", history: history)
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])

        await vm.loadHistoryIfNeeded()
        await vm.loadHistoryIfNeeded()

        XCTAssertEqual(repo.loadCallCount, 1)
        XCTAssertEqual(repo.analyzeCallCount, 0)
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.first?.content, "Find my biggest mistakes")
    }

    func testNewPromptAppendsWithoutOverwritingHistory() async {
        let trade = makeTrade()
        let history = [
            TradeAIMessage(role: .user, content: "Find my biggest mistakes", promptKey: "mistakes"),
            TradeAIMessage(role: .assistant, content: coachReply),
        ]
        let repo = MockAIRepository(reply: "Fresh reply", history: history)
        let vm = TradeAISectionViewModel(tradeID: trade.id, ai: repo)
        vm.updateContext(trade: trade, notes: [])
        await vm.loadHistoryIfNeeded()

        vm.selectedPrompt = TradeAISuggestedPrompts.all.first { $0.id == "execution" }!
        await vm.analyzeSelected()

        XCTAssertEqual(vm.messages.count, 4)
        XCTAssertEqual(vm.messages[0].content, "Find my biggest mistakes")
        XCTAssertEqual(vm.messages[2].content, "Evaluate my execution")
        XCTAssertEqual(vm.messages[3].content, "Fresh reply")
        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertEqual(repo.persistedBatches.count, 1)
    }

    func testContextExtensionPointsExistWithoutUICoupling() {
        var context = TradeAIMapper.makeContext(trade: makeTrade())
        context.accountStatisticsSummary = "Win rate 54%"
        context.strategyHistorySummary = "ORB last 20"
        context.previousTradesSummary = "3 winners this week"
        context.linkedClipIDs = [ReelID("clip-1")]
        XCTAssertNotNil(context.accountStatisticsSummary)
        XCTAssertEqual(context.linkedClipIDs.count, 1)
    }

    func testAppConfigurationResolvesBFFBaseURLForAnalyzeTrade() throws {
        let withSecret = AppConfiguration.make(
            for: .debug,
            secrets: SecretsLoader.Values(
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                apiBaseURL: URL(string: "https://www.tradetraxs.com")
            )
        )
        XCTAssertEqual(withSecret.apiBaseURL?.absoluteString, "https://www.tradetraxs.com")

        let debugFallback = AppConfiguration.make(
            for: .debug,
            secrets: SecretsLoader.Values(
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                apiBaseURL: nil
            )
        )
        XCTAssertEqual(debugFallback.apiBaseURL, AppConfiguration.productionBFFBaseURL)

        let productionFallback = AppConfiguration.make(
            for: .production,
            secrets: SecretsLoader.Values(
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                apiBaseURL: nil
            )
        )
        XCTAssertEqual(productionFallback.apiBaseURL, AppConfiguration.productionBFFBaseURL)
        XCTAssertEqual(productionFallback.apiBaseURL, AppConfiguration.defaultBFFBaseURL)

        let env = EnvironmentConfiguration.make(for: .debug, appConfiguration: debugFallback)
        XCTAssertEqual(
            env.bffBaseURL?.absoluteString,
            "https://www.tradetraxs.com"
        )
        let builder = RequestBuilder(configuration: NetworkConfiguration.make(environment: env))
        let analyze = try builder.makeRequest(
            endpoint: Endpoint(host: .bff, path: "/api/analyze-trade", method: .post),
            body: Data("{}".utf8)
        )
        XCTAssertEqual(
            analyze.url.absoluteString,
            "https://www.tradetraxs.com/api/analyze-trade"
        )
        XCTAssertEqual(analyze.headers["Content-Type"], "application/json")

        let pushRegister = try builder.makeRequest(
            endpoint: Endpoint(host: .bff, path: "/api/push/register", method: .post),
            body: Data("{}".utf8)
        )
        XCTAssertEqual(
            pushRegister.url.absoluteString,
            "https://www.tradetraxs.com/api/push/register"
        )

        let productionEnv = EnvironmentConfiguration.make(
            for: .production,
            appConfiguration: productionFallback
        )
        let productionBuilder = RequestBuilder(
            configuration: NetworkConfiguration.make(environment: productionEnv)
        )
        let productionPush = try productionBuilder.makeRequest(
            endpoint: Endpoint(host: .bff, path: "/api/push/register", method: .post),
            body: Data("{}".utf8)
        )
        XCTAssertEqual(
            productionPush.url.absoluteString,
            "https://www.tradetraxs.com/api/push/register"
        )
    }

    func testMissingBFFConfigurationShowsFriendlyCopy() {
        let mapped = UserFacingError.map(
            NetworkError.validation(statusCode: nil, message: "Base URL for bff is not configured")
        )
        XCTAssertFalse(mapped.message.contains("NetworkError"))
        XCTAssertFalse(mapped.message.contains("error 3"))
        XCTAssertTrue(mapped.message.localizedCaseInsensitiveContains("available"))
    }

    private var coachReply: String {
        """
        ## Verdict
        🟡 Good idea, poor execution.

        ## Biggest Insight
        Risk was fine; management was not.

        ## Key Improvements
        - Hold to plan
        - Size after RR
        - Journal exit first

        ## Next Trade Focus
        Pre-commit the exit before you click buy.
        """
    }

    private func makeTrade() -> Trade {
        Trade(
            id: TradeID("00000000-0000-4000-8000-000000000701"),
            ownerProfileID: ProfileID("00000000-0000-4000-8000-000000000702"),
            accountID: nil,
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: Decimal(string: "21450"),
            exitPrice: Decimal(string: "21480"),
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_300),
            realizedPnL: Money(amount: 300, currencyCode: "USD"),
            riskReward: Decimal(string: "2.5"),
            points: Decimal(string: "30"),
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: "ORB continuation",
            thumbnail: MediaReference(id: "trades/shot.png", kind: .image, altText: nil),
            notePreview: nil,
            strategy: "ORB",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
    }
}

private final class MockAIRepository: AIRepository, @unchecked Sendable {
    var reply: String
    var history: [TradeAIMessage]
    private(set) var analyzeCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var lastRequest: TradeAIAnalyzeRequest?
    private(set) var persistedBatches: [[TradeAIMessage]] = []

    init(reply: String, history: [TradeAIMessage] = []) {
        self.reply = reply
        self.history = history
    }

    func analyzeTrade(_ request: TradeAIAnalyzeRequest) async throws -> TradeAIAnalyzeResponse {
        analyzeCallCount += 1
        lastRequest = request
        return TradeAIAnalyzeResponse(reply: reply)
    }

    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage] {
        loadCallCount += 1
        return history
    }

    func persistMessages(_ messages: [TradeAIMessage], tradeID: TradeID) async throws {
        persistedBatches.append(messages)
    }

    func explainPsychologyCoach(_ request: PsychologyCoachAIRequest) async throws -> PsychologyCoachAIResponse {
        PsychologyCoachAIResponse(reply: reply)
    }

    func extractScreenshotTrades(_ request: ScreenshotAIExtractRequest) async throws -> ScreenshotAIExtractResponse {
        throw AppError.notImplemented(feature: "extractScreenshotTrades")
    }
}
