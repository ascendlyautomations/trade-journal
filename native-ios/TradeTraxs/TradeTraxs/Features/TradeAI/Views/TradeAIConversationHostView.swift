import SwiftUI

/// Navigation host — owns ``TradeAISectionViewModel`` for a trade thread.
struct TradeAIConversationHostView: View {
    let tradeID: TradeID
    let conversationID: AIConversationID?
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: TradeAISectionViewModel

    init(
        tradeID: TradeID,
        conversationID: AIConversationID?,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.tradeID = tradeID
        self.conversationID = conversationID
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: TradeAISectionViewModel(tradeID: tradeID, ai: data.ai)
        )
    }

    var body: some View {
        TradeAIConversationView(
            viewModel: viewModel,
            tradeID: tradeID,
            imagePipeline: data.imagePipeline,
            onOpenTradeDetail: { id in
                navigationCoordinator.pushHome(.tradeDetail(id))
            }
        )
        .onAppear {
            if let conversationID {
                viewModel.noteConversationID(conversationID)
            }
        }
        .task(id: tradeID) {
            await hydrateTradeContext()
        }
    }

    private func hydrateTradeContext() async {
        if let conversationID {
            viewModel.noteConversationID(conversationID)
        }
        if let cached = data.detailCache.trade(id: tradeID) {
            viewModel.updateContext(trade: cached, notes: [])
            data.detailCache.seedPresentationSeed(
                TradeSummaryMapper.presentationSeed(fromListTrade: cached)
            )
            return
        }
        if let loaded = try? await data.trades.trade(id: tradeID) {
            viewModel.updateContext(trade: loaded, notes: [])
            data.detailCache.seedPresentationSeed(
                TradeSummaryMapper.presentationSeed(fromListTrade: loaded)
            )
        }
    }
}