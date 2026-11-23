import Foundation

/// DEBUG instrumentation for Trade Room category — filter in Xcode console: `TRADE_ROOM_CATEGORY`
#if DEBUG
enum TradeRoomCategoryRuntimeProbe {
    static let demoTradeRoomID = RoomID("ab8e192f-5da0-477e-958b-1a83fc6e31af")
    private static let optionsOfficialID = RoomID("9d38241f-6ac5-4781-9468-d6d252417778")

    nonisolated static func logDecode(
        roomID: RoomID,
        name: String,
        rawRPCCategory: String?,
        decoded: TradeRoomCategory?,
        section: String
    ) {
        guard isTracked(roomID) else { return }
        print(
            """
            [TRADE_ROOM_CATEGORY] decode section=\(section) \
            id=\(roomID.rawValue) name=\(name) \
            rawRPC=\(rawRPCCategory ?? "nil") decoded=\(categoryLabel(decoded))
            """
        )
    }

    @MainActor
    static func logApplyBootstrap(
        source: RoomDiscoveryProbe.DisplayedSource,
        fingerprintChanged: Bool,
        bootstrap: TradeRoomsHomeBootstrap,
        popularItems: [ExploreRoomSuggestion],
        inboxRooms: [TradeRoom]
    ) {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        print(
            """
            [TRADE_ROOM_CATEGORY] applyBootstrap source=\(source.rawValue) \
            build=\(build) fingerprintChanged=\(fingerprintChanged) \
            popularDecoded=\(bootstrap.popular.count)
            """
        )
        logRoomSnapshot(
            tag: "bootstrap.popular",
            suggestions: bootstrap.popular
        )
        logRoomSnapshot(tag: "popularItems", suggestions: popularItems)
        logInboxCategories(inboxRooms)
    }

    @MainActor
    static func logCategoryFilter(
        scope: TradeRoomDiscoveryScope,
        filter: TradeRoomCategory?,
        displayedCollection: String,
        displayed: [ExploreRoomSuggestion],
        popularSource: [ExploreRoomSuggestion],
        effectiveFor: (ExploreRoomSuggestion) -> TradeRoomCategory?
    ) {
        let filterLabel = filter?.rawValue ?? "all"
        print(
            """
            [TRADE_ROOM_CATEGORY] filter scope=\(scope.rawValue) \
            filter=\(filterLabel) collection=\(displayedCollection) \
            displayedCount=\(displayed.count) popularSourceCount=\(popularSource.count)
            """
        )
        print(
            "[TRADE_ROOM_CATEGORY] displayedIDs=\(displayed.map(\.id.rawValue).joined(separator: ","))"
        )
        for room in displayed.prefix(12) {
            let eff = effectiveFor(room)
            print(
                """
                [TRADE_ROOM_CATEGORY] row id=\(room.id.rawValue) \
                name=\(room.name) suggestionCategory=\(categoryLabel(room.category)) \
                effective=\(categoryLabel(eff))
                """
            )
        }
        logRoomSnapshot(tag: "popularItems(source)", suggestions: popularSource)
    }

    @MainActor
    static func logManageRoomLoad(room: TradeRoom, source: String) {
        print(
            """
            [TRADE_ROOM_CATEGORY] manageLoad source=\(source) \
            id=\(room.id.rawValue) name=\(room.name) \
            persistedCategory=\(categoryLabel(room.category))
            """
        )
    }

    @MainActor
    private static func logRoomSnapshot(tag: String, suggestions: [ExploreRoomSuggestion]) {
        for id in [demoTradeRoomID, optionsOfficialID] {
            guard let room = suggestions.first(where: { $0.id == id }) else { continue }
            print(
                """
                [TRADE_ROOM_CATEGORY] \(tag) id=\(room.id.rawValue) \
                suggestionCategory=\(categoryLabel(room.category)) slug=\(room.slug)
                """
            )
        }
    }

    @MainActor
    private static func logInboxCategories(_ rooms: [TradeRoom]) {
        for id in [demoTradeRoomID, optionsOfficialID] {
            guard let room = rooms.first(where: { $0.id == id }) else { continue }
            print(
                """
                [TRADE_ROOM_CATEGORY] inbox id=\(room.id.rawValue) \
                cachedCategory=\(categoryLabel(room.category))
                """
            )
        }
    }

    nonisolated private static func isTracked(_ id: RoomID) -> Bool {
        id == demoTradeRoomID || id == optionsOfficialID
    }

    nonisolated private static func categoryLabel(_ category: TradeRoomCategory?) -> String {
        category?.rawValue ?? "nil"
    }
}
#else
enum TradeRoomCategoryRuntimeProbe {
    static let demoTradeRoomID = RoomID("ab8e192f-5da0-477e-958b-1a83fc6e31af")

    nonisolated static func logDecode(
        roomID: RoomID,
        name: String,
        rawRPCCategory: String?,
        decoded: TradeRoomCategory?,
        section: String
    ) {}

    @MainActor
    static func logApplyBootstrap(
        source: RoomDiscoveryProbe.DisplayedSource,
        fingerprintChanged: Bool,
        bootstrap: TradeRoomsHomeBootstrap,
        popularItems: [ExploreRoomSuggestion],
        inboxRooms: [TradeRoom]
    ) {}

    @MainActor
    static func logCategoryFilter(
        scope: TradeRoomDiscoveryScope,
        filter: TradeRoomCategory?,
        displayedCollection: String,
        displayed: [ExploreRoomSuggestion],
        popularSource: [ExploreRoomSuggestion],
        effectiveFor: (ExploreRoomSuggestion) -> TradeRoomCategory?
    ) {}

    @MainActor
    static func logManageRoomLoad(room: TradeRoom, source: String) {}
}
#endif