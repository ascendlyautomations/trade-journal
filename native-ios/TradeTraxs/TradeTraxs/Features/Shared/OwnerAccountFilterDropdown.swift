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

    struct ContentModel {
        let accounts: [TradingAccount]
        let isAllAccountsSelected: Bool
        let selectedAccountID: TradingAccountID?
        let onSelectAll: () -> Void
        let onSelectAccount: (TradingAccountID) -> Void
        let onManageAccounts: () -> Void
    }

    func present(sourceID: String, anchorFrame: CGRect, content: ContentModel) {
        self.sourceID = sourceID
        self.anchorFrame = anchorFrame
        self.content = content
        isPresented = true
        presentationRevision &+= 1
    }

    func dismiss() {
        isPresented = false
        self.content = nil
        sourceID = ""
        anchorFrame = .zero
        presentationRevision &+= 1
    }
}

// MARK: - Selector button

/// Owner account filter dropdown — root overlay presentation (not ``Menu`` / ``popover``).
struct OwnerAccountFilterDropdown<Trigger: View>: View {
    let accounts: [TradingAccount]
    let isAllAccountsSelected: Bool
    let selectedAccountID: TradingAccountID?
    let onSelectAll: () -> Void
    let onSelectAccount: (TradingAccountID) -> Void
    let onManageAccounts: () -> Void
    let accessibilityIdentifier: String
    var boundary: OwnerAccountDropdownSupport.Boundary?
    var profileID: ProfileID?
    @ViewBuilder let trigger: () -> Trigger

    @State private var anchorFrame: CGRect = .zero

    private var controller: OwnerAccountFilterDropdownController { .shared }

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            controller.present(
                sourceID: accessibilityIdentifier,
                anchorFrame: anchorFrame,
                content: .init(
                    accounts: accounts,
                    isAllAccountsSelected: isAllAccountsSelected,
                    selectedAccountID: selectedAccountID,
                    onSelectAll: {
                        onSelectAll()
                        controller.dismiss()
                    },
                    onSelectAccount: { id in
                        onSelectAccount(id)
                        controller.dismiss()
                    },
                    onManageAccounts: {
                        onManageAccounts()
                        controller.dismiss()
                    }
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
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .anchorPreference(
            key: OwnerAccountDropdownAnchorsKey.self,
            value: .bounds,
            transform: { anchor in
                [accessibilityIdentifier: anchor]
            }
        )
        .onAppear {
            if let boundary {
                OwnerAccountDropdownSupport.logBoundary(
                    boundary,
                    accounts: accounts,
                    profileID: profileID
                )
            }
        }
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
    /// Hosts the floating account filter panel above the tab shell — not clipped by scroll views.
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
                        screenHeight: proxy.size.height
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

    @Environment(\.themeColors) private var colors

    private var dividerHeight: CGFloat { max(ExperienceBorder.hairline, 1) }
    private var accountsScrollHeight: CGFloat {
        CGFloat(content.accounts.count) * OwnerAccountDropdownSupport.filterMenuAccountRowHeight
    }
    private var maxAccountsScrollHeight: CGFloat {
        OwnerAccountDropdownSupport.filterMenuMaxAccountsScrollHeight(screenHeight: screenHeight)
    }
    private var usesScrollingAccounts: Bool {
        accountsScrollHeight > maxAccountsScrollHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(
                title: "All Accounts",
                isSelected: content.isAllAccountsSelected,
                rowHeight: OwnerAccountDropdownSupport.filterMenuAllAccountsRowHeight,
                action: content.onSelectAll
            )
            panelDivider
            accountsSection
            panelDivider
            actionRow(
                title: "Manage Accounts",
                systemImage: "slider.horizontal.3",
                isSelected: false,
                rowHeight: OwnerAccountDropdownSupport.filterMenuManageAccountsRowHeight,
                action: content.onManageAccounts
            )
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

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.accounts) { account in
                accountRow(account)
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: TradingAccount) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            content.onSelectAccount(account.id)
        } label: {
            OwnerAccountDropdownFilterRow(
                account: account,
                isSelected: content.selectedAccountID == account.id
            )
            .padding(.horizontal, ExperienceSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        systemImage: String? = nil,
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
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(height: rowHeight)
        }
        .buttonStyle(.plain)
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
