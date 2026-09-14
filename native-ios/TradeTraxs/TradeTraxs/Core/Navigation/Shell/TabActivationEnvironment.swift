import SwiftUI

/// True when this tab's content is the selected tab — offscreen TabView children stay false.
private struct TabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var tabIsActive: Bool {
        get { self[TabIsActiveKey.self] }
        set { self[TabIsActiveKey.self] = newValue }
    }
}

extension View {
    func tabActivation(isActive: Bool) -> some View {
        environment(\.tabIsActive, isActive)
    }
}
