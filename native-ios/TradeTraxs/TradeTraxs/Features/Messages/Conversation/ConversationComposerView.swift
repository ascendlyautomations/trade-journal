import SwiftUI
import UIKit

struct ConversationComposerView: View {
    @Bindable var viewModel: ConversationViewModel

    var body: some View {
        MessageComposerBar(
            draft: $viewModel.draft,
            isSending: viewModel.isSending,
            onSend: {
                Task { await viewModel.sendText() }
            },
            onSendImage: { image in
                Task { await viewModel.sendImage(image) }
            },
            onSendTrade: {
                viewModel.presentTradePicker()
            }
        )
        .sheet(isPresented: $viewModel.showsTradePicker) {
            TradeSharePickerSheet(
                trades: viewModel.tradePickerTrades,
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
