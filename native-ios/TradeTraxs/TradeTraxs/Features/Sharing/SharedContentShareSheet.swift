import SwiftUI
import UIKit

struct SharedContentShareSheet: View {
    let target: SharedContentShareTarget
    let data: DataEnvironment
    var tradeOwnerShareAccess: TradeOwnerShareAccess?
    var onTradeVisibilityUpdated: ((Trade) -> Void)?
    var onClose: () -> Void

    @State private var viewModel: SharedContentShareViewModel
    @State private var recipientScope: SharedContentShareViewModel.RecipientScope?
    @State private var showsExternalShare = false
    @State private var resolvedOwnerVisibility: ContentVisibility?
    @State private var makePublicConfirm: MakePublicShareConfirm?
    @State private var isMakingPublic = false
    @State private var makePublicErrorMessage: String?

    @Environment(\.themeColors) private var colors

    private enum MakePublicShareConfirm: Identifiable {
        case copyLink
        case externalShare

        var id: String {
            switch self {
            case .copyLink: return "copy"
            case .externalShare: return "external"
            }
        }

        var confirmTitle: String {
            switch self {
            case .copyLink: return "Make Public & Copy Link"
            case .externalShare: return "Make Public & Share"
            }
        }
    }

    init(
        target: SharedContentShareTarget,
        data: DataEnvironment,
        tradeOwnerShareAccess: TradeOwnerShareAccess? = nil,
        onTradeVisibilityUpdated: ((Trade) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.target = target
        self.data = data
        self.tradeOwnerShareAccess = tradeOwnerShareAccess
        self.onTradeVisibilityUpdated = onTradeVisibilityUpdated
        self.onClose = onClose
        _resolvedOwnerVisibility = State(initialValue: tradeOwnerShareAccess?.visibility)
        _viewModel = State(
            initialValue: SharedContentShareViewModel(
                target: target,
                messagesRepo: data.messages,
                roomsRepo: data.rooms,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    private var requiresPublicLinkAccess: Bool {
        guard let access = tradeOwnerShareAccess else { return false }
        let visibility = resolvedOwnerVisibility ?? access.visibility
        return visibility == .private
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Send in TradeTraxs") {
                    Button {
                        recipientScope = .messages
                    } label: {
                        Label("Messages", systemImage: "message")
                    }
                    .accessibilityIdentifier("sharedContentShare.messages")

                    Button {
                        recipientScope = .rooms
                    } label: {
                        Label("Trade Rooms", systemImage: "person.3")
                    }
                    .accessibilityIdentifier("sharedContentShare.tradeRooms")
                }

                Section("Share Externally") {
                    if target.contentLink.url != nil {
                        Button {
                            requestCopyLink()
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                        .disabled(isMakingPublic)
                        .accessibilityIdentifier("sharedContentShare.copyLink")
                    }

                    if target.contentLink.url != nil {
                        Button {
                            requestExternalShare()
                        } label: {
                            Label("Share Externally", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isMakingPublic)
                        .accessibilityIdentifier("sharedContentShare.external")
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .experienceScreenBackground()
            .navigationTitle(target.shareTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .experienceSheetChrome()
        .sheet(item: $recipientScope) { scope in
            SharedContentShareRecipientPickerView(
                scope: scope,
                viewModel: viewModel,
                imagePipeline: data.imagePipeline,
                onSendSuccess: {
                    recipientScope = nil
                    onClose()
                },
                onClose: { recipientScope = nil }
            )
        }
        .sheet(isPresented: $showsExternalShare) {
            if let url = target.contentLink.url {
                SharedContentExternalShareSheet(
                    items: [viewModel.externalShareText, url]
                )
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .sent, recipientScope != nil {
                recipientScope = nil
                onClose()
            }
        }
        .confirmationDialog(
            "Share this private trade?",
            isPresented: Binding(
                get: { makePublicConfirm != nil },
                set: { if !$0 { makePublicConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirm = makePublicConfirm {
                Button(confirm.confirmTitle) {
                    let pending = confirm
                    makePublicConfirm = nil
                    Task { await performMakePublicThen(confirm: pending) }
                }
            }
            Button("Cancel", role: .cancel) {
                makePublicConfirm = nil
            }
        } message: {
            Text(
                "This trade is private. People you share the link with can't open it on TradeTraxs unless sharing access is enabled."
            )
        }
        .alert(
            "Couldn't update trade",
            isPresented: Binding(
                get: { makePublicErrorMessage != nil },
                set: { if !$0 { makePublicErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { makePublicErrorMessage = nil }
        } message: {
            Text(makePublicErrorMessage ?? "")
        }
    }

    private func requestCopyLink() {
        if requiresPublicLinkAccess {
            makePublicConfirm = .copyLink
        } else {
            DetailOverflowActions.copyLink(target.contentLink)
        }
    }

    private func requestExternalShare() {
        if requiresPublicLinkAccess {
            makePublicConfirm = .externalShare
        } else {
            showsExternalShare = true
        }
    }

    @MainActor
    private func performMakePublicThen(confirm: MakePublicShareConfirm) async {
        guard let access = tradeOwnerShareAccess else { return }
        guard let trade = await resolvedTrade(for: access.tradeID) else {
            makePublicErrorMessage = "We couldn't load this trade. Try again."
            return
        }
        isMakingPublic = true
        defer { isMakingPublic = false }
        do {
            let updated = try await JournalTradeShareSupport.makePublicForSharing(
                trade: trade,
                trades: data.trades,
                session: data.session
            )
            resolvedOwnerVisibility = .public
            onTradeVisibilityUpdated?(updated)
            switch confirm {
            case .copyLink:
                DetailOverflowActions.copyLink(target.contentLink)
            case .externalShare:
                showsExternalShare = true
            }
        } catch {
            makePublicErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    private func resolvedTrade(for tradeID: TradeID) async -> Trade? {
        if let trade = data.detailCache.trade(id: tradeID) {
            return trade
        }
        return try? await data.trades.trade(id: tradeID)
    }
}

private struct SharedContentExternalShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum SharedContentNavigation {
    @MainActor
    static func open(
        reference: SharedContentReference,
        cache: DetailPresentationCache,
        coordinator: NavigationCoordinator?,
        host: TradeRoomNavigationHost? = nil,
        hydrationContext: SharedContentHydrator.Context? = nil,
        hydrationSurface: SharedContentHydrationProbe.Surface = .dm
    ) {
        Task {
            await openAsync(
                reference: reference,
                cache: cache,
                coordinator: coordinator,
                host: host,
                hydrationContext: hydrationContext,
                hydrationSurface: hydrationSurface
            )
        }
    }

    @MainActor
    static func openAsync(
        reference: SharedContentReference,
        cache: DetailPresentationCache,
        coordinator: NavigationCoordinator?,
        host: TradeRoomNavigationHost? = nil,
        hydrationContext: SharedContentHydrator.Context? = nil,
        hydrationSurface: SharedContentHydrationProbe.Surface = .dm
    ) async {
        guard let coordinator else { return }
        if let hydrationContext {
            _ = await SharedContentHydrator.hydrateForOpen(
                reference: reference,
                context: hydrationContext,
                surface: hydrationSurface
            )
        }
        if let host {
            coordinator.pushSharedContent(reference, cache: cache, host: host)
            return
        }
        navigate(
            reference: reference,
            cache: cache,
            coordinator: coordinator
        )
    }

    @MainActor
    private static func navigate(
        reference: SharedContentReference,
        cache: DetailPresentationCache,
        coordinator: NavigationCoordinator
    ) {
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                let preview =
                    cache.presentationSeed(id: tradeID)?.previewTrade
                    ?? cache.previewTrade(id: tradeID)
                coordinator.pushSocialTrade(tradeID, cache: cache, preview: preview)
            } else {
                coordinator.pushPostDetail(postID, loadSource: .feedPost)
            }
        case .profilePost(let postID):
            coordinator.pushPostDetail(postID, loadSource: .profilePost)
        case .achievementPost(let postID):
            coordinator.pushAchievementDetail(AchievementID(postID.rawValue))
        case .reel(let reelID):
            coordinator.pushReelDetail(reelID)
        case .trade(let tradeID):
            let preview =
                cache.presentationSeed(id: tradeID)?.previewTrade
                ?? cache.previewTrade(id: tradeID)
            coordinator.pushSocialTrade(tradeID, cache: cache, preview: preview)
        case .traderProfile(let profileID):
            coordinator.pushOtherProfile(profileID)
        }
    }
}
