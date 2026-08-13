import SwiftUI

extension View {
    /// TradeTraxs navigation convention: the screen name lives in the compact top bar.
    ///
    /// - Root pages: title only (e.g. Dashboard, Feed, Messages).
    /// - Subpages: system Back + this title (e.g. Calendar, Notifications, Trading Day).
    ///
    /// Always inline — do not use `.navigationBarTitleDisplayMode(.large)`.
    /// Do not also render the same page name as a large heading in scroll content.
    ///
    /// Uses `.principal` so the title stays visually centered on the screen even when
    /// leading/trailing toolbar items have unequal widths (e.g. Calendar vs Bell).
    /// Screens that need a richer principal header may still attach their own
    /// `.toolbar { ToolbarItem(placement: .principal) … }` afterward — later principal
    /// content wins.
    func experienceNavigationTitle(_ title: some StringProtocol) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
