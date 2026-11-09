import SwiftUI
import UIKit

struct ConversationComposerView: View {
    @Bindable var viewModel: ConversationViewModel
    let imagePipeline: any ImagePipeline

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
            MessageComposerBar(
            draft: $viewModel.draft,
            isSending: viewModel.isSending,
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
                onSelect: { trade in
                    Task { await viewModel.sendTrade(trade) }
                },
                onClose: {
                    viewModel.showsTradePicker = false
                }
            )
            .task {
                await viewModel.loadTradePickerIfNeeded()
            }
        }
    }
}
