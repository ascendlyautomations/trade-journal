import SwiftUI
import UIKit

struct ConversationComposerView: View {
    @Bindable var viewModel: ConversationViewModel
    let imagePipeline: any ImagePipeline

    @State private var pendingPrivateTradeConfirm: Trade?

    var body: some View {
        VStack(spacing: 0) {
            if let target = viewModel.replyTarget {
                MessageReplyComposerStrip(
                    authorName: target.authorName,
                    preview: target.preview,
                    onCancel: { viewModel.clearReply() }
                )
                .padding(.horizontal, ExperienceSpacing.xs)
                .padding(.top, ExperienceSpacing.xxs)
            }
            if let trade = viewModel.pendingSharedTrade {
                MessageComposerTradeStagingRow(
                    trade: trade,
                    imagePipeline: imagePipeline,
                    onRemove: { viewModel.clearPendingSharedTrade() }
                )
                .padding(.top, ExperienceSpacing.xxs)
            }
            MessageComposerBar(
                draft: $viewModel.draft,
                isSending: viewModel.isSending,
                hasStagedTrade: viewModel.pendingSharedTrade != nil,
                onSend: {
                    Task { await viewModel.sendText() }
                },
                onSendImage: { image in
                    Task { await viewModel.sendImage(image) }
                },
                onSendVoice: { url, duration in
                    Task { await viewModel.sendVoice(localFileURL: url, duration: duration) }
                },
                onSendTrade: {
                    viewModel.presentTradePicker()
                }
            )
        }
        .sheet(isPresented: $viewModel.showsTradePicker) {
            TradeSharePickerSheet(
                trades: viewModel.tradePickerTrades,
                imagePipeline: imagePipeline,
                isLoading: viewModel.isLoadingTradePicker,
                title: "Attach Trade",
                onSelect: { trade in
                    if trade.visibility == .private {
                        pendingPrivateTradeConfirm = trade
                    } else {
                        viewModel.stageSharedTrade(trade)
                    }
                },
                onClose: {
                    viewModel.showsTradePicker = false
                }
            )
            .task {
                await viewModel.loadTradePickerIfNeeded()
            }
        }
        .alert(
            "Attach private trade?",
            isPresented: Binding(
                get: { pendingPrivateTradeConfirm != nil },
                set: { if !$0 { pendingPrivateTradeConfirm = nil } }
            )
        ) {
            Button("Attach") {
                if let trade = pendingPrivateTradeConfirm {
                    viewModel.stageSharedTrade(trade)
                }
                pendingPrivateTradeConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPrivateTradeConfirm = nil
            }
        } message: {
            Text(CommentTradeShareSupport.privateAttachmentDisclaimer)
        }
    }
}