import SwiftUI
import UIKit

struct SharedContentShareSheet: View {
    let target: SharedContentShareTarget
    let data: DataEnvironment
    var onClose: () -> Void

    @State private var viewModel: SharedContentShareViewModel
    @State private var recipientScope: SharedContentShareViewModel.RecipientScope?
    @State private var showsExternalShare = false

    @Environment(\.themeColors) private var colors

    init(
        target: SharedContentShareTarget,
        data: DataEnvironment,
        onClose: @escaping () -> Void
    ) {
        self.target = target
        self.data = data
        self.onClose = onClose
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
                            DetailOverflowActions.copyLink(target.contentLink)
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                        .accessibilityIdentifier("sharedContentShare.copyLink")
                    }

                    if target.contentLink.url != nil {
                        Button {
                            showsExternalShare = true
                        } label: {
                            Label("Share Externally", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("sharedContentShare.external")
                    }
                }
            }
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
        host: TradeRoomNavigationHost? = nil
    ) {
        guard let coordinator else { return }
        if let host {
            coordinator.pushSharedContent(reference, cache: cache, host: host)
            return
        }
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                coordinator.pushSocialTrade(tradeID, cache: cache)
            } else {
                coordinator.pushPostDetail(postID)
            }
        case .profilePost(let postID):
            coordinator.pushPostDetail(postID)
        case .achievementPost(let postID):
            coordinator.pushAchievementDetail(AchievementID(postID.rawValue))
        case .reel(let reelID):
            coordinator.pushReelDetail(reelID)
        case .trade(let tradeID):
            coordinator.pushSocialTrade(tradeID, cache: cache)
        }
    }
}
