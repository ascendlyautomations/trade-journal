import Foundation

#if DEBUG
/// Lifecycle / load tracing for Trade Rooms home regressions — not per-render.
enum TradeRoomsHomeLifecycleProbe {
    nonisolated static func viewModelInit(id: String) {
        print("[TradeRoomsHome] vm.init id=\(id)")
    }

    nonisolated static func viewModelDeinit(id: String) {
        print("[TradeRoomsHome] vm.deinit id=\(id)")
    }

    nonisolated static func viewAppear(id: String) {
        print("[TradeRoomsHome] view.appear vm=\(id)")
    }

    nonisolated static func viewDisappear(id: String) {
        print("[TradeRoomsHome] view.disappear vm=\(id)")
    }

    nonisolated static func hostingTabActive(id: String, active: Bool) {
        print("[TradeRoomsHome] hostingTabActive vm=\(id) active=\(active)")
    }

    nonisolated static func performLoad(
        id: String,
        phase: String,
        forceNetwork: Bool,
        event: String
    ) {
        print(
            "[TradeRoomsHome] performLoad vm=\(id) event=\(event) "
                + "forceNetwork=\(forceNetwork) phase=\(phase)"
        )
    }

    nonisolated static func loadHomeBootstrap(
        id: String,
        event: String,
        hostingTabActive: Bool,
        forceNetwork: Bool
    ) {
        print(
            "[TradeRoomsHome] loadHomeBootstrap vm=\(id) event=\(event) "
                + "hostingTabActive=\(hostingTabActive) forceNetwork=\(forceNetwork)"
        )
    }

    nonisolated static func realtime(id: String, event: String) {
        print("[TradeRoomsHome] realtime vm=\(id) event=\(event)")
    }
}
#else
enum TradeRoomsHomeLifecycleProbe {
    nonisolated static func viewModelInit(id: String) {}
    nonisolated static func viewModelDeinit(id: String) {}
    nonisolated static func viewAppear(id: String) {}
    nonisolated static func viewDisappear(id: String) {}
    nonisolated static func hostingTabActive(id: String, active: Bool) {}
    nonisolated static func performLoad(id: String, phase: String, forceNetwork: Bool, event: String) {}
    nonisolated static func loadHomeBootstrap(id: String, event: String, hostingTabActive: Bool, forceNetwork: Bool) {}
    nonisolated static func realtime(id: String, event: String) {}
}
#endif
