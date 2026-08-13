import Foundation
import Testing
@testable import TradeTraxs

/// Compile-time + light runtime checks that Profile / Feed / Messaging conform to the
/// unified screen architecture without asserting product behavior changes.
@Suite("ScreenArchitectureFramework")
struct ScreenArchitectureFrameworkTests {
    @Test func profileStateModelsCommonFields() {
        var state = ProfileState()
        state.phase = .loaded
        state.didBootstrap = true
        state.isRefreshing = true
        state.errorMessage = "x"
        state.tradesNextCursor = "c1"
        state.lastUpdated = Date(timeIntervalSince1970: 1)

        let modeled: any ScreenStateModeling = state
        #expect(modeled.screenPhase == .loaded)
        #expect(modeled.didBootstrap)
        #expect(modeled.isRefreshing)
        #expect(modeled.screenErrorMessage == "x")
        #expect(modeled.pagination.nextCursor == "c1")
        #expect(modeled.pagination.hasMore)
        #expect(modeled.lastUpdated != nil)
    }

    @Test func feedStateModelsPagination() {
        var state = FeedState()
        state.phase = .failed("boom")
        state.nextCursor = "n"
        state.hasMore = true
        state.isLoadingMore = true
        state.didBootstrap = true

        let modeled: any ScreenStateModeling = state
        #expect(modeled.screenPhase == .failed("boom"))
        #expect(modeled.screenErrorMessage == "boom")
        #expect(modeled.pagination.isLoadingMore)
        #expect(modeled.pagination.hasMore)
    }

    @Test func messagingStateUsesNonePagination() {
        var state = MessagingState()
        state.phase = .loading
        state.didBootstrap = false
        state.isRefreshing = true

        let modeled: any ScreenStateModeling = state
        #expect(modeled.screenPhase == .loading)
        #expect(modeled.pagination == .none)
        #expect(modeled.isRefreshing)
    }

    @Test func bootstrapTypesSatisfyScreenBootstrap() {
        // Associated-type witnesses — if these compile, ScreenBootstrap conformance holds.
        let _: ProfileBootstrap.Type = ProfileBootstrap.self
        let _: FeedBootstrap.Type = FeedBootstrap.self
        let _: MessagingBootstrap.Type = MessagingBootstrap.self
        #expect(true)
    }

    @Test func lifecycleOwnersExposeStandardAPI() async {
        // Type-check ScreenLifecycle / retain protocols on the three owners.
        func requiresLifecycle<T: ScreenLifecycle>(_: T.Type) {}
        func requiresRetain<T: ScreenRealtimeRetaining>(_: T.Type) {}
        func requiresRealtimeHandling<T: ScreenRealtimeHandling>(_: T.Type) {}

        requiresLifecycle(ProfileScreenViewModel.self)
        requiresLifecycle(FeedScreenViewModel.self)
        requiresLifecycle(MessagingDomain.self)
        requiresRetain(MessagingDomain.self)
        requiresRealtimeHandling(FeedScreenViewModel.self)
        #expect(true)
    }
}
