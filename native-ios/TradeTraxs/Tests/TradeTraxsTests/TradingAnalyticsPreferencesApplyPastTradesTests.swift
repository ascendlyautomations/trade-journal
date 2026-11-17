import XCTest
@testable import TradeTraxs

@MainActor
final class TradingAnalyticsPreferencesApplyPastTradesTests: XCTestCase {
    private let userID = ProfileID("apply-past-trades-user")

    func testToggleMarksUnsavedWithoutOtherEdits() async {
        let repo = InMemoryTradingPreferencesRepository()
        let viewModel = makeViewModel(repository: repo)

        await viewModel.load()
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.applyRulesToPastTrades)

        viewModel.applyRulesToPastTrades = true
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testSavePersistsApplyPastTradesOnAndOff() async throws {
        let repo = InMemoryTradingPreferencesRepository()

        let first = makeViewModel(repository: repo)
        await first.load()
        first.applyRulesToPastTrades = true
        let savedOn = await first.saveAll()
        XCTAssertTrue(savedOn)

        let reloadedOn = makeViewModel(repository: repo)
        await reloadedOn.load()
        XCTAssertTrue(reloadedOn.applyRulesToPastTrades)
        XCTAssertFalse(reloadedOn.hasUnsavedChanges)

        let storedOn = try await repo.globalPreferences(for: userID)
        XCTAssertTrue(storedOn.applyRulesToPastTrades)

        reloadedOn.applyRulesToPastTrades = false
        let savedOff = await reloadedOn.saveAll()
        XCTAssertTrue(savedOff)

        let reloadedOff = makeViewModel(repository: repo)
        await reloadedOff.load()
        XCTAssertFalse(reloadedOff.applyRulesToPastTrades)

        let storedOff = try await repo.globalPreferences(for: userID)
        XCTAssertFalse(storedOff.applyRulesToPastTrades)
    }

    func testDiscardRestoresSavedApplyPastTrades() async throws {
        let repo = InMemoryTradingPreferencesRepository()
        var stored = TradingPreferenceGlobal.empty(userID: userID)
        stored.applyRulesToPastTrades = true
        _ = try await repo.saveGlobal(stored)

        let viewModel = makeViewModel(repository: repo)
        await viewModel.load()
        XCTAssertTrue(viewModel.applyRulesToPastTrades)

        viewModel.applyRulesToPastTrades = false
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        viewModel.discardChanges()

        XCTAssertTrue(viewModel.applyRulesToPastTrades)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testLoadDoesNotOverwriteUnsavedToggle() async throws {
        let repo = InMemoryTradingPreferencesRepository()
        var stored = TradingPreferenceGlobal.empty(userID: userID)
        stored.applyRulesToPastTrades = false
        _ = try await repo.saveGlobal(stored)

        let viewModel = makeViewModel(repository: repo)
        await viewModel.load()
        viewModel.applyRulesToPastTrades = true
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        var server = stored
        server.applyRulesToPastTrades = false
        _ = try await repo.saveGlobal(server)

        await viewModel.load()
        XCTAssertTrue(viewModel.applyRulesToPastTrades, "Background load must not discard an unsaved toggle")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testForceLoadAppliesServerValueAfterSave() async throws {
        let repo = InMemoryTradingPreferencesRepository()

        let editor = makeViewModel(repository: repo)
        await editor.load()
        editor.applyRulesToPastTrades = true
        let saved = await editor.saveAll()
        XCTAssertTrue(saved)

        var server = try await repo.globalPreferences(for: userID)
        server.applyRulesToPastTrades = false
        _ = try await repo.saveGlobal(server)

        let otherDevice = makeViewModel(repository: repo)
        await otherDevice.load()
        XCTAssertFalse(otherDevice.applyRulesToPastTrades)
    }

    func testComplianceFingerprintChangesWhenApplyPastToggles() {
        var global = TradingPreferenceGlobal.empty(userID: userID)
        global.applyRulesToPastTrades = false
        let off = PreferenceRuleContext(revisions: [], global: global, overrides: [])

        global.applyRulesToPastTrades = true
        let on = PreferenceRuleContext(revisions: [], global: global, overrides: [])

        XCTAssertNotEqual(
            PreferenceComplianceEngine.fingerprint(off),
            PreferenceComplianceEngine.fingerprint(on)
        )
    }

    private func makeViewModel(
        repository: InMemoryTradingPreferencesRepository
    ) -> TradingAnalyticsPreferencesViewModel {
        TradingAnalyticsPreferencesViewModel(
            repository: repository,
            session: ApplyPastTradesStubSession(userID: userID),
            detailCache: DetailPresentationCache(),
            loadAccounts: { _ in [] }
        )
    }
}

// MARK: - Test doubles

private actor InMemoryTradingPreferencesRepository: TradingPreferencesRepository {
    private var global: TradingPreferenceGlobal?
    private var overrides: [TradingPreferenceAccountOverride] = []

    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal {
        global?.userID == userID ? (global ?? .empty(userID: userID)) : .empty(userID: userID)
    }

    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal {
        global = preferences
        return preferences
    }

    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride] {
        _ = userID
        return overrides
    }

    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride {
        overrides.removeAll { $0.accountID == override.accountID }
        overrides.append(override)
        return override
    }

    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision] {
        _ = userID
        return []
    }

    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse? {
        _ = userID
        return nil
    }

    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse {
        _ = (response, userID)
        return response
    }

    func hasJournalTrade(for userID: ProfileID) async throws -> Bool {
        _ = userID
        return false
    }
}

private struct ApplyPastTradesStubSession: SessionProviding {
    let userID: ProfileID

    var currentUserID: UserID? {
        get async { UserID(userID.rawValue) }
    }

    var accessToken: String? {
        get async { "test-token" }
    }
}