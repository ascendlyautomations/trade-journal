import OSLog
import SwiftUI

struct SettingsHomeView: View {
    let authenticationCoordinator: AuthenticationCoordinator

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var launchController = AppLaunchController.shared
    @State private var confirmsLogout = false
    @State private var monetizationConfigRevision = 0
    @State private var showsAdminEntry = false
    @State private var settingsListGlobalFrame: CGRect = .zero
    @State private var settingsListSafeArea: EdgeInsets = .init()
    @State private var tradingRulesTourRowFrame: CGRect = .zero
    #if DEBUG
    @State private var clipCacheClearConfirmation = false
    @State private var isClearingClipVideoCache = false
    #endif

    var body: some View {
        ScrollViewReader { tourProxy in
        List {
            if launchController.isDemoExperienceActive {
                Section {
                    Button {
                        launchController.exitDemoExplore(authIntent: .createAccount)
                    } label: {
                        SettingsNavigationRow(
                            title: "Create Account",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    Button {
                        launchController.exitDemoExplore()
                    } label: {
                        SettingsNavigationRow(
                            title: "Exit Guest Mode",
                            systemImage: "arrow.backward.circle",
                            isDestructive: true
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.exitGuestMode")
                } header: {
                    Text("Guest Mode")
                }
            }

            if showsAdminEntry, !launchController.isDemoExperienceActive {
                Section {
                    Button {
                        ExperienceHaptics.play(.selection)
                        openAdminPortal()
                    } label: {
                        SettingsNavigationRow(title: "Admin", systemImage: "shield")
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.row.admin")
                } header: {
                    Text("Internal")
                }
            }

            let _ = monetizationConfigRevision
            ForEach(SettingsHomeModel.sections) { section in
                Section {
                    if section.id == "tradetraxs" {
                        Button {
                            ExperienceHaptics.play(.selection)
                            ContextualTourDebug.logTourTrace("settings replay button action received")
                            ContextualTourCoordinator.shared.beginReplay()
                        } label: {
                            SettingsNavigationRow(
                                title: "App Walkthrough",
                                systemImage: "play.circle"
                            )
                        }
                        .buttonStyle(.experiencePlain)
                        .accessibilityIdentifier("settings.row.appWalkthrough")
                    }
                    ForEach(section.items) { item in
                        Button {
                            ExperienceHaptics.play(.selection)
                            stackNavigation?.pushSettings(item.route)
                        } label: {
                            SettingsNavigationRow(
                                title: item.rowTitle,
                                systemImage: item.systemImage
                            )
                        }
                        .buttonStyle(.experiencePlain)
                        .accessibilityIdentifier("settings.row.\(item.route.rawValue)")
                        .modifier(SettingsAppearanceTourTarget(isAppearance: item.route == .appearance))
                        .modifier(
                            SettingsTradingRulesTourTarget(
                                isTradingRules: item.route == .tradingAnalytics,
                                rowGlobalFrame: $tradingRulesTourRowFrame
                            )
                        )
                    }
                    if section.id == "tradetraxs" {
                        Button {
                            ExperienceHaptics.play(.selection)
                            guard let url = AppStoreProductReview.writeReviewURL() else { return }
                            openURL(url)
                        } label: {
                            SettingsNavigationRow(
                                title: "Leave a Rating",
                                systemImage: "star"
                            )
                        }
                        .buttonStyle(.experiencePlain)
                        .accessibilityIdentifier("settings.row.leaveRating")
                    }
                } header: {
                    Text(section.title)
                }
            }

            #if DEBUG
            if !launchController.isDemoExperienceActive {
                Section {
                    Button {
                        isClearingClipVideoCache = true
                        Task {
                            await ClipVideoDeliveryDebugControls.clearClipVideoCache()
                            isClearingClipVideoCache = false
                            clipCacheClearConfirmation = true
                        }
                    } label: {
                        SettingsNavigationRow(
                            title: "Clear Clip Video Cache",
                            systemImage: "externaldrive.badge.minus"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(isClearingClipVideoCache)
                    .accessibilityIdentifier("settings.debug.clearClipVideoCache")
                    Button {
                        ContextualTourCoordinator.shared.resetStoredTourForDebug()
                    } label: {
                        SettingsNavigationRow(
                            title: "Reset App Tour",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.debug.resetAppTour")
                    Button {
                        Task {
                            await PerformanceReportReminderCoordinator.shared.scheduleDebugProbesForTesting()
                        }
                    } label: {
                        SettingsNavigationRow(
                            title: "Test Performance Report Notifications",
                            systemImage: "bell.badge"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.debug.performanceReportReminders")
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug only. Reset App Tour clears this account’s tour completion, then open Dashboard. Clear Clip Video Cache removes the Clip MP4 disk cache. Performance report test schedules one weekly and one monthly local notification in ~90s.")
                }
            }
            #endif

            if !launchController.isDemoExperienceActive {
                Section {
                    Button {
                        confirmsLogout = true
                    } label: {
                        SettingsNavigationRow(
                            title: "Log Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            isDestructive: true
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.logout")
                }
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.xxs)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { _, insets in
                        settingsListSafeArea = insets
                    }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
            settingsListGlobalFrame = frame
        }
        .experienceNavigationTitle("Settings")
        .confirmationDialog(
            "Log out of TradeTraxs?",
            isPresented: $confirmsLogout,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                ExperienceHaptics.play(.selection)
                Task { await authenticationCoordinator.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
        #if DEBUG
        .alert("Clip video cache cleared", isPresented: $clipCacheClearConfirmation) {
            Button("OK", role: .cancel) {}
        }
        #endif
        .accessibilityIdentifier("settings.home")
        .onAppear {
            #if DEBUG
            AppLog.navigation.debug("settings.home.appeared")
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            monetizationConfigRevision += 1
        }
        .onDisappear {
            #if DEBUG
            AppLog.navigation.debug("settings.home.disappeared")
            #endif
        }
        .task {
            showsAdminEntry = SessionBootstrapStore.shared.isPlatformAdmin
            await refreshMonetizationConfigurationForSettings()
        }
        .onAppear {
            ContextualTourCoordinator.shared.noteSettingsHomeLaidOut()
            scrollSettingsTourIfNeeded(using: tourProxy)
        }
        .onChange(of: ContextualTourCoordinator.shared.scrollGeneration) { _, _ in
            scrollSettingsTourIfNeeded(using: tourProxy)
        }
        .onChange(of: ContextualTourCoordinator.shared.spotlightTarget) { _, _ in
            scrollSettingsTourIfNeeded(using: tourProxy)
        }
        .onChange(of: ContextualTourCoordinator.shared.stepRevision) { _, _ in
            scrollSettingsTourIfNeeded(using: tourProxy)
        }
        .onChange(of: tradingRulesTourRowFrame) { _, _ in
            alignTradingRulesTourScrollIfNeeded(using: tourProxy)
        }
        .onChange(of: settingsListGlobalFrame) { _, _ in
            alignTradingRulesTourScrollIfNeeded(using: tourProxy)
        }
        }
    }

    private func scrollSettingsTourIfNeeded(using proxy: ScrollViewProxy) {
        let coordinator = ContextualTourCoordinator.shared
        guard coordinator.phase == .preparing || coordinator.phase == .presenting else { return }
        guard let target = coordinator.spotlightTarget else { return }
        switch target {
        case .settingsAppearance:
            scrollSettingsTourRow(using: proxy, target: target, coordinator: coordinator)
        case .settingsTradingRules:
            scrollSettingsTradingRulesTourRow(using: proxy, coordinator: coordinator)
        default:
            return
        }
    }

    /// Appearance (S18) scroll path — unchanged.
    private func scrollSettingsTourRow(
        using proxy: ScrollViewProxy,
        target: ContextualTourTargetID,
        coordinator: ContextualTourCoordinator
    ) {
        let anchor = ContextualTourGeometry.scrollAnchor(for: target)
        withAnimation(ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)) {
            proxy.scrollTo(target, anchor: anchor)
        }
        DispatchQueue.main.async {
            coordinator.noteScrollTargetLayoutChanged()
        }
    }

    /// Trading Rules (S19): scroll so row center sits at 25% of the tour visible viewport (geometry-derived anchor).
    private func scrollSettingsTradingRulesTourRow(
        using proxy: ScrollViewProxy,
        coordinator: ContextualTourCoordinator
    ) {
        let target = ContextualTourTargetID.settingsTradingRules
        let anchor = tradingRulesTourScrollUnitPoint(
            rowMidY: tradingRulesTourRowFrame.height > 1 ? tradingRulesTourRowFrame.midY : nil
        )
        proxy.scrollTo(target, anchor: anchor)
        DispatchQueue.main.async {
            coordinator.noteScrollTargetLayoutChanged()
        }
    }

    private func alignTradingRulesTourScrollIfNeeded(using proxy: ScrollViewProxy) {
        let coordinator = ContextualTourCoordinator.shared
        guard coordinator.phase == .preparing,
              coordinator.spotlightTarget == .settingsTradingRules
        else { return }
        guard tradingRulesTourRowFrame.height > 1,
              let targetMidY = tradingRulesTourTargetRowCenterY()
        else { return }

        let tolerance: CGFloat = 2
        guard abs(tradingRulesTourRowFrame.midY - targetMidY) > tolerance else { return }

        let anchor = tradingRulesTourScrollUnitPoint(rowMidY: tradingRulesTourRowFrame.midY)
        proxy.scrollTo(ContextualTourTargetID.settingsTradingRules, anchor: anchor)
        DispatchQueue.main.async {
            coordinator.noteScrollTargetLayoutChanged()
        }
    }

    /// Tour-visible mid-Y for the Trading Rules row center (overlay measurement insets, list-local top).
    private func tradingRulesTourTargetRowCenterY() -> CGFloat? {
        let listFrame = settingsListGlobalFrame
        guard listFrame.height > 1 else { return nil }

        let topInset = ExperienceSpacing.sm
            + ContextualTourGeometry.measurementTopInset(for: .settingsTradingRules)
        let bottomInset = settingsTourMeasurementBottomInset(safeBottom: settingsListSafeArea.bottom)
        let visibleHeight = max(0, listFrame.height - topInset - bottomInset)
        guard visibleHeight > 1 else { return nil }

        return listFrame.minY + topInset + visibleHeight * 0.25
    }

    private func settingsTourMeasurementBottomInset(safeBottom: CGFloat) -> CGFloat {
        let tabReserve: CGFloat
        if safeBottom >= 49 {
            tabReserve = safeBottom + ExperienceSpacing.xs
        } else {
            tabReserve = safeBottom + 49 + ExperienceSpacing.xs
        }
        return tabReserve + ContextualTourGeometry.measurementBottomInset(for: .settingsTradingRules)
    }

    private func tradingRulesTourScrollUnitPoint(rowMidY: CGFloat?) -> UnitPoint {
        guard let targetMidY = tradingRulesTourTargetRowCenterY() else {
            return UnitPoint(x: 0.5, y: 0.25)
        }
        let listFrame = settingsListGlobalFrame
        guard listFrame.height > 1 else {
            return UnitPoint(x: 0.5, y: 0.25)
        }

        var anchorY = (targetMidY - listFrame.minY) / listFrame.height
        if let rowMidY {
            let error = rowMidY - targetMidY
            anchorY -= error / listFrame.height
        }

        let clampedY = min(max(anchorY, 0.02), 0.98)
        return UnitPoint(x: 0.5, y: clampedY)
    }

    private func refreshMonetizationConfigurationForSettings() async {
        guard !launchController.isDemoExperienceActive else { return }
        guard let userID = await appEnvironment.data.session.currentUserID else { return }
        guard let refresher = appEnvironment.data.billing as? MonetizationConfigurationRefreshing else { return }
        await refresher.refreshMonetizationConfiguration(for: ProfileID(userID.rawValue))
        if IosSubscriptionReleaseConfiguration.iosPaywallEnabled {
            await appEnvironment.data.storeKitSubscriptions.startTransactionListenerIfNeeded()
        }
    }

    private func openAdminPortal() {
        #if DEBUG
        AppLog.navigation.debug(
            "settings.admin.row.tapped isPlatformAdmin=\(SessionBootstrapStore.shared.isPlatformAdmin, privacy: .public)"
        )
        #endif
        if let stackNavigation {
            stackNavigation.pushSettings(.admin)
            #if DEBUG
            AppLog.navigation.debug("settings.route.admin pushed via=stackNavigation")
            #endif
        } else {
            appEnvironment.navigation.coordinator.pushProfile(.settings(.admin))
            #if DEBUG
            AppLog.navigation.debug("settings.route.admin pushed via=pushProfile")
            #endif
        }
    }
}

/// Spotlight only the Appearance row. Other settings rows stay unchanged.
private struct SettingsAppearanceTourTarget: ViewModifier {
    let isAppearance: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAppearance {
            content.contextualTourTarget(.settingsAppearance)
        } else {
            content
        }
    }
}

/// Spotlight only the Trading Rules row on Settings home.
private struct SettingsTradingRulesTourTarget: ViewModifier {
    let isTradingRules: Bool
    @Binding var rowGlobalFrame: CGRect

    @ViewBuilder
    func body(content: Content) -> some View {
        if isTradingRules {
            content
                .contextualTourTarget(.settingsTradingRules)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
                    rowGlobalFrame = frame
                }
        } else {
            content
        }
    }
}


