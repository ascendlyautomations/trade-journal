import SwiftUI
import Combine

// MARK: - Coordinate space

private enum OwnerAccountDropdownCoordinateSpace {
    static let name = "ownerAccountFilterDropdown.overlay"
}

// MARK: - Anchor preference

private struct OwnerAccountDropdownAnchorsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Presentation controller

@MainActor
final class OwnerAccountFilterDropdownController: ObservableObject {
    static let shared = OwnerAccountFilterDropdownController()

    @Published private(set) var isPresented = false
    @Published private(set) var sourceID = ""
    @Published private(set) var anchorFrame: CGRect = .zero
    @Published private(set) var content: ContentModel?
    @Published var anchors: [String: Anchor<CGRect>] = [:]
    @Published private(set) var presentationRevision = 0
    @Published var panel: OwnerAccountFilterDropdownPanelView = .accounts

    enum OwnerAccountFilterDropdownPanelView: Equatable {
        case accounts
        case copyTrading
    }

    struct ContentModel {
        let accounts: [TradingAccount]
        let selectedFilter: DashboardAccountFilter
        let copyGroups: [CopyTradingGroup]
        let isLoadingCopyGroups: Bool
        var includesCopyTradingMenu: Bool = true
        let onSelectFilter: (DashboardAccountFilter) -> Void
        let onManageAccounts: () -> Void
        let onManageCopyGroups: () -> Void
        let onRequestCopyGroups: () -> Void
    }

    func present(sourceID: String, anchorFrame: CGRect, content: ContentModel) {
        panel = .accounts
        self.sourceID = sourceID
        self.anchorFrame = anchorFrame
        self.content = content
        isPresented = true
        presentationRevision &+= 1
        content.onRequestCopyGroups()
    }

    func dismiss() {
        isPresented = false
        panel = .accounts
        self.content = nil
        sourceID = ""
        anchorFrame = .zero
        presentationRevision &+= 1
    }
}

// MARK: - Selector button

/// Owner account filter dropdown, root overlay presentation (not ``Menu`` / ``popover``).
struct OwnerAccountFilterDropdown<Trigger: View>: View {
    let accounts: [TradingAccount]
    let selectedFilter: DashboardAccountFilter
    let copyGroups: [CopyTradingGroup]
    let isLoadingCopyGroups: Bool
    let onSelectFilter: (DashboardAccountFilter) -> Void
    let onManageAccounts: () -> Void
    let onManageCopyGroups: () -> Void
    let onRequestCopyGroups: () -> Void
    let accessibilityIdentifier: String
    var includesCopyTradingMenu: Bool = true
    var boundary: OwnerAccountDropdownSupport.Boundary?
    var profileID: ProfileID?
    var detailCache: DetailPresentationCache?
    @ViewBuilder let trigger: () -> Trigger

    @State private var anchorFrame: CGRect = .zero

    private var controller: OwnerAccountFilterDropdownController { .shared }

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            if let boundary {
                OwnerAccountDropdownSupport.logBoundary(
                    boundary,
                    accounts: accounts,
                    profileID: profileID,
                    detailCache: detailCache
                )
            }
            controller.present(
                sourceID: accessibilityIdentifier,
                anchorFrame: anchorFrame,
                content: .init(
                    accounts: accounts,
                    selectedFilter: selectedFilter,
                    copyGroups: copyGroups,
                    isLoadingCopyGroups: isLoadingCopyGroups,
                    includesCopyTradingMenu: includesCopyTradingMenu,
                    onSelectFilter: { filter in
                        onSelectFilter(filter)
                        controller.dismiss()
                    },
                    onManageAccounts: {
                        onManageAccounts()
                        controller.dismiss()
                    },
                    onManageCopyGroups: {
                        onManageCopyGroups()
                        controller.dismiss()
                    },
                    onRequestCopyGroups: onRequestCopyGroups
                )
            )
        } label: {
            trigger()
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        anchorFrame = geo.frame(in: .named(OwnerAccountDropdownCoordinateSpace.name))
                    }
                    .onChange(of: geo.frame(in: .named(OwnerAccountDropdownCoordinateSpace.name))) { _, frame in
                        anchorFrame = frame
                    }
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .anchorPreference(
            key: OwnerAccountDropdownAnchorsKey.self,
            value: .bounds,
            transform: { anchor in
                [accessibilityIdentifier: anchor]
            }
        )
    }
}

// MARK: - Root overlay host

private struct OwnerAccountFilterDropdownOverlayHost: ViewModifier {
    func body(content: Content) -> some View {
        OwnerAccountFilterDropdownOverlayRoot(content: content)
    }
}

private struct OwnerAccountFilterDropdownOverlayRoot<Content: View>: View {
    @ObservedObject(wrappedValue: OwnerAccountFilterDropdownController.shared) private var controller
    let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            OwnerAccountFilterDropdownOverlayLayer()
                .allowsHitTesting(controller.isPresented)
        }
        .coordinateSpace(name: OwnerAccountDropdownCoordinateSpace.name)
        .onPreferenceChange(OwnerAccountDropdownAnchorsKey.self) { anchors in
            controller.anchors = anchors
        }
    }
}

extension View {
    /// Hosts the floating account filter panel above the tab shell, not clipped by scroll views.
    func ownerAccountFilterDropdownOverlay() -> some View {
        modifier(OwnerAccountFilterDropdownOverlayHost())
    }
}

private struct OwnerAccountFilterDropdownOverlayLayer: View {
    @ObservedObject(wrappedValue: OwnerAccountFilterDropdownController.shared) private var controller

    var body: some View {
        GeometryReader { proxy in
            if controller.isPresented,
               let content = controller.content {
                let anchorRect = resolvedAnchorRect(in: proxy, anchors: controller.anchors)
                let screenWidth = proxy.size.width
                let panelWidth = OwnerAccountDropdownSupport.filterMenuPanelWidth(screenWidth: screenWidth)
                let originX = OwnerAccountDropdownSupport.clampedPanelOriginX(
                    anchorMinX: anchorRect.minX,
                    panelWidth: panelWidth,
                    screenWidth: screenWidth
                )
                let originY = anchorRect.maxY + OwnerAccountDropdownSupport.filterMenuPanelSpacingBelowAnchor

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            controller.dismiss()
                        }
                        .accessibilityLabel("Dismiss account filter")
                        .accessibilityAddTraits(.isButton)

                    OwnerAccountFilterDropdownPanel(
                        content: content,
                        screenHeight: proxy.size.height,
                        panel: controller.panel,
                        onPanelChange: { controller.panel = $0 }
                    )
                        .frame(width: panelWidth, alignment: .leading)
                        .offset(x: originX, y: originY)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(10_000)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.16), value: controller.presentationRevision)
    }

    private func resolvedAnchorRect(
        in proxy: GeometryProxy,
        anchors: [String: Anchor<CGRect>]
    ) -> CGRect {
        if let anchor = anchors[controller.sourceID] {
            return proxy[anchor]
        }
        return controller.anchorFrame
    }
}

// MARK: - Panel

private struct OwnerAccountFilterDropdownPanel: View {
    let content: OwnerAccountFilterDropdownController.ContentModel
    let screenHeight: CGFloat
    let panel: OwnerAccountFilterDropdownController.OwnerAccountFilterDropdownPanelView
    let onPanelChange: (OwnerAccountFilterDropdownController.OwnerAccountFilterDropdownPanelView) -> Void

    @Environment(\.themeColors) private var colors

    private var dividerHeight: CGFloat { max(ExperienceBorder.hairline, 1) }
    private var accountsScrollHeight: CGFloat {
        CGFloat(accountsForMainMenu.count) * OwnerAccountDropdownSupport.filterMenuAccountRowHeight
    }
    private var maxAccountsScrollHeight: CGFloat {
        OwnerAccountDropdownSupport.filterMenuMaxAccountsScrollHeight(screenHeight: screenHeight)
    }
    private var usesScrollingAccounts: Bool {
        accountsScrollHeight > maxAccountsScrollHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch panel {
            case .accounts:
                accountsPanel
            case .copyTrading:
                copyTradingPanel
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.border.opacity(0.55), lineWidth: ExperienceBorder.hairline)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .accessibilityIdentifier("ownerAccountFilter.dropdown.panel")
        .accessibilityElement(children: .contain)
    }

    private var accountsPanel: some View {
        Group {
            actionRow(
                title: "All Accounts",
                isSelected: content.selectedFilter.isAllAccountsSelection,
                rowHeight: OwnerAccountDropdownSupport.filterMenuAllAccountsRowHeight
            ) {
                content.onSelectFilter(.all)
            }
            if content.includesCopyTradingMenu {
                panelDivider
                actionRow(
                    title: "Copy Trading",
                    systemImage: "arrow.triangle.branch",
                    showsChevron: true,
                    isSelected: content.selectedFilter.isCopyTradingScoped
                        || copyAccountSelectionActive,
                    rowHeight: OwnerAccountDropdownSupport.filterMenuAllAccountsRowHeight
                ) {
                    onPanelChange(.copyTrading)
                }
                .accessibilityIdentifier("ownerAccountFilter.dropdown.copyTradingEntry")
                panelDivider
            }
            accountsSection
            panelDivider
            actionRow(
                title: "Manage Accounts",
                systemImage: "slider.horizontal.3",
                isSelected: false,
                rowHeight: OwnerAccountDropdownSupport.filterMenuManageAccountsRowHeight
            ) {
                content.onManageAccounts()
            }
        }
    }

    private var copyAccountSelectionActive: Bool {
        guard let id = content.selectedFilter.selectedAccountID else { return false }
        let linked = DashboardAccountFilterCopyTradingSupport.linkedAccountIDs(from: content.copyGroups)
        return linked.contains(id.rawValue)
    }

    private var copyTradingPanel: some View {
        Group {
            actionRow(
                title: "Accounts",
                systemImage: "chevron.left",
                isSelected: false,
                rowHeight: OwnerAccountDropdownSupport.filterMenuAllAccountsRowHeight
            ) {
                onPanelChange(.accounts)
            }
            .accessibilityIdentifier("ownerAccountFilter.dropdown.copyTradingBack")
            panelDivider
            actionRow(
                title: "All Copy Trading Accounts",
                isSelected: content.selectedFilter == .copyTradingAll,
                rowHeight: OwnerAccountDropdownSupport.filterMenuAllAccountsRowHeight
            ) {
                content.onSelectFilter(.copyTradingAll)
            }
            panelDivider
            copyTradingListSection
            panelDivider
            actionRow(
                title: "Manage Copy Trading Groups",
                systemImage: "slider.horizontal.3",
                isSelected: false,
                rowHeight: OwnerAccountDropdownSupport.filterMenuManageAccountsRowHeight
            ) {
                content.onManageCopyGroups()
            }
        }
    }

    @ViewBuilder
    private var copyTradingListSection: some View {
        if content.isLoadingCopyGroups, content.copyGroups.isEmpty {
            HStack(spacing: 8) {
                selectionMark(isSelected: false)
                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceIndeterminateProgress(controlSize: .small)
                    Text("Loading copy trading…")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(
                height: OwnerAccountDropdownSupport.filterMenuAccountRowHeight,
                alignment: .leading
            )
        } else if content.copyGroups.isEmpty {
            HStack(spacing: 8) {
                selectionMark(isSelected: false)
                Text("No copy trading groups yet.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(
                height: OwnerAccountDropdownSupport.filterMenuAccountRowHeight,
                alignment: .leading
            )
        } else {
            copyTradingScrollContent
        }
    }

    @ViewBuilder
    private var copyTradingScrollContent: some View {
        let rowCount = content.copyGroups.count
        let scrollHeight = CGFloat(rowCount) * OwnerAccountDropdownSupport.filterMenuAccountRowHeight
        let maxHeight = OwnerAccountDropdownSupport.filterMenuMaxAccountsScrollHeight(screenHeight: screenHeight)
        let list = VStack(alignment: .leading, spacing: 0) {
            ForEach(content.copyGroups, id: \.id) { group in
                copyGroupRow(group)
            }
        }
        if scrollHeight > maxHeight {
            ScrollView { list }
                .frame(height: maxHeight)
        } else {
            list
        }
    }

    private func copyGroupRow(_ group: CopyTradingGroup) -> some View {
        let isSelected: Bool = {
            if case .copyTradingGroup(let id) = content.selectedFilter { return id == group.id }
            return false
        }()
        return Button {
            ExperienceHaptics.play(.selection)
            content.onSelectFilter(.copyTradingGroup(group.id))
        } label: {
            HStack(spacing: 8) {
                selectionMark(isSelected: isSelected)
                Text(group.name)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(height: OwnerAccountDropdownSupport.filterMenuAccountRowHeight)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("ownerAccountFilter.dropdown.copyGroup.\(group.id)")
    }

    @ViewBuilder
    private var accountsSection: some View {
        if usesScrollingAccounts {
            ScrollView {
                accountsList
            }
            .frame(height: maxAccountsScrollHeight)
        } else {
            accountsList
        }
    }

    private var accountsForMainMenu: [TradingAccount] {
        DashboardAccountFilterCopyTradingSupport.standaloneMenuAccounts(
            from: content.accounts,
            copyGroups: content.copyGroups,
            preservingSelection: content.selectedFilter.selectedAccountID
        )
    }

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(accountsForMainMenu) { account in
                accountRow(account)
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: TradingAccount) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            content.onSelectFilter(.account(account.id))
        } label: {
            OwnerAccountDropdownFilterRow(
                account: account,
                isSelected: content.selectedFilter.selectedAccountID == account.id
            )
            .padding(.horizontal, ExperienceSpacing.sm)
        }
        .buttonStyle(.experiencePlain)
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        systemImage: String? = nil,
        showsChevron: Bool = false,
        isSelected: Bool,
        rowHeight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                selectionMark(isSelected: isSelected)
                if let systemImage {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(.footnote)
                        Text(title)
                            .experienceStyle(.footnote, color: colors.primaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(title)
                        .experienceStyle(.footnote, color: colors.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(height: rowHeight)
        }
        .buttonStyle(.experiencePlain)
    }

    @ViewBuilder
    private func selectionMark(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.accent)
            } else {
                Color.clear
            }
        }
        .frame(width: 18, alignment: .center)
        .accessibilityHidden(true)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(colors.border.opacity(0.55))
            .frame(height: dividerHeight)
    }
}
