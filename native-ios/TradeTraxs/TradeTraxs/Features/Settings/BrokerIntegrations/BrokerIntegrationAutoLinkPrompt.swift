import SwiftUI

/// Session-local guard so dismissing the link sheet without linking does not immediately re-prompt.
@MainActor
@Observable
final class BrokerIntegrationLinkPromptGate {
    private(set) var dismissedMappingIDs: Set<String> = []
    private(set) var lastPresentedMappingID: String?
    private(set) var autoLinkSequenceActive = false

    var excludedFromAutoPrompt: Set<String> { dismissedMappingIDs }

    func beginAutoLinkSequence() {
        autoLinkSequenceActive = true
    }

    func endAutoLinkSequence() {
        autoLinkSequenceActive = false
    }

    func recordPresentation(mappingID: String) {
        lastPresentedMappingID = mappingID
    }

    func handleLinkSheetDismissed(viewModel: BrokerIntegrationsViewModel) {
        defer { lastPresentedMappingID = nil }
        guard let mappingID = lastPresentedMappingID else { return }
        guard mappingStillUnlinked(mappingID, in: viewModel) else { return }
        dismissedMappingIDs.insert(mappingID)
        endAutoLinkSequence()
    }

    func noteSuccessfulLink(mappingID: String) {
        dismissedMappingIDs.remove(mappingID)
        if lastPresentedMappingID == mappingID {
            lastPresentedMappingID = nil
        }
    }

    private func mappingStillUnlinked(
        _ mappingID: String,
        in viewModel: BrokerIntegrationsViewModel
    ) -> Bool {
        for connection in viewModel.tradovateConnections + viewModel.rithmicConnections {
            guard let account = viewModel.accounts(for: connection.id).first(where: { $0.id == mappingID })
            else { continue }
            return !account.hasTradetraxsMapping
        }
        return false
    }
}

/// Presents ``BrokerLinkExistingAccountSheet`` when unlinked broker accounts exist after connect.
@MainActor
enum BrokerIntegrationAutoLinkPrompt {
    static func schedule(
        viewModel: BrokerIntegrationsViewModel,
        gate: BrokerIntegrationLinkPromptGate,
        linkTarget: Binding<BrokerIntegrationLinkTarget?>,
        createLinkTarget: Binding<BrokerIntegrationCreateLinkTarget?>,
        onExpandConnectedLogin: ((BrokerIntegrationProvider, String) -> Void)? = nil
    ) {
        Task { @MainActor in
            await waitUntilReadyForPresentation(viewModel)
            presentIfNeeded(
                viewModel: viewModel,
                gate: gate,
                linkTarget: linkTarget,
                createLinkTarget: createLinkTarget,
                onExpandConnectedLogin: onExpandConnectedLogin
            )
        }
    }

    static func waitUntilReadyForPresentation(_ viewModel: BrokerIntegrationsViewModel) async {
        for _ in 0 ..< 120 {
            if blocksLinkPrompt(viewModel) || viewModel.isDiscoveringBrokerAccountsAfterConnect {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            return
        }
    }

    private static func blocksLinkPrompt(_ viewModel: BrokerIntegrationsViewModel) -> Bool {
        viewModel.isBrokerConnectionMutationActive
            || viewModel.showsRithmicConnectSheet
            || viewModel.showsTradovateEnvironmentPicker
    }

    private static func presentIfNeeded(
        viewModel: BrokerIntegrationsViewModel,
        gate: BrokerIntegrationLinkPromptGate,
        linkTarget: Binding<BrokerIntegrationLinkTarget?>,
        createLinkTarget: Binding<BrokerIntegrationCreateLinkTarget?>,
        onExpandConnectedLogin: ((BrokerIntegrationProvider, String) -> Void)?
    ) {
        guard linkTarget.wrappedValue == nil, createLinkTarget.wrappedValue == nil else { return }
        guard !blocksLinkPrompt(viewModel) else { return }

        guard gate.autoLinkSequenceActive || viewModel.shouldAttemptAutoLinkPrompt else { return }

        guard let next = viewModel.firstUnlinkedBrokerAccount(
            excludingMappingIDs: gate.excludedFromAutoPrompt
        ) else {
            if viewModel.isDiscoveringBrokerAccountsAfterConnect {
                return
            }
            gate.endAutoLinkSequence()
            viewModel.clearAutoLinkPromptRequest()
            return
        }

        if viewModel.shouldAttemptAutoLinkPrompt {
            gate.beginAutoLinkSequence()
            viewModel.clearAutoLinkPromptRequest()
            onExpandConnectedLogin?(next.provider, next.connectionId)
        }

        gate.recordPresentation(mappingID: next.account.id)
        linkTarget.wrappedValue = BrokerIntegrationLinkTarget(
            provider: next.provider,
            connectionId: next.connectionId,
            account: next.account
        )
    }
}

extension View {
    @MainActor
    @ViewBuilder
    func brokerIntegrationAutoLinkPromptIfReady(
        viewModel: BrokerIntegrationsViewModel?,
        gate: BrokerIntegrationLinkPromptGate,
        linkTarget: Binding<BrokerIntegrationLinkTarget?>,
        createLinkTarget: Binding<BrokerIntegrationCreateLinkTarget?>,
        onExpandConnectedLogin: ((BrokerIntegrationProvider, String) -> Void)? = nil
    ) -> some View {
        if let viewModel {
            brokerIntegrationAutoLinkPrompt(
                viewModel: viewModel,
                gate: gate,
                linkTarget: linkTarget,
                createLinkTarget: createLinkTarget,
                onExpandConnectedLogin: onExpandConnectedLogin
            )
        } else {
            self
        }
    }

    @MainActor
    func brokerIntegrationAutoLinkPrompt(
        viewModel: BrokerIntegrationsViewModel,
        gate: BrokerIntegrationLinkPromptGate,
        linkTarget: Binding<BrokerIntegrationLinkTarget?>,
        createLinkTarget: Binding<BrokerIntegrationCreateLinkTarget?>,
        onExpandConnectedLogin: ((BrokerIntegrationProvider, String) -> Void)? = nil
    ) -> some View {
        modifier(
            BrokerIntegrationAutoLinkPromptModifier(
                viewModel: viewModel,
                gate: gate,
                linkTarget: linkTarget,
                createLinkTarget: createLinkTarget,
                onExpandConnectedLogin: onExpandConnectedLogin
            )
        )
    }
}

private struct BrokerIntegrationAutoLinkPromptModifier: ViewModifier {
    @Bindable var viewModel: BrokerIntegrationsViewModel
    var gate: BrokerIntegrationLinkPromptGate
    @Binding var linkTarget: BrokerIntegrationLinkTarget?
    @Binding var createLinkTarget: BrokerIntegrationCreateLinkTarget?
    var onExpandConnectedLogin: ((BrokerIntegrationProvider, String) -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.unlinkedBrokerAccountsCount) { _, _ in
                requestPrompt()
            }
            .onChange(of: viewModel.hasActiveConnectedBroker) { _, _ in
                requestPrompt()
            }
            .onChange(of: viewModel.shouldAttemptAutoLinkPrompt) { _, should in
                guard should else { return }
                requestPrompt()
            }
            .onChange(of: viewModel.isBrokerConnectionMutationActive) { wasActive, isActive in
                guard wasActive, !isActive else { return }
                requestPrompt()
            }
            .onChange(of: viewModel.showsRithmicConnectSheet) { wasShowing, isShowing in
                guard wasShowing, !isShowing else { return }
                requestPrompt()
            }
            .onChange(of: viewModel.brokerAccountsDiscoveryBusy) { _, _ in
                requestPrompt()
            }
            .onChange(of: viewModel.showsTradovateEnvironmentPicker) { wasShowing, isShowing in
                guard wasShowing, !isShowing else { return }
                requestPrompt()
            }
    }

    private func requestPrompt() {
        guard gate.autoLinkSequenceActive || viewModel.shouldAttemptAutoLinkPrompt else { return }
        BrokerIntegrationAutoLinkPrompt.schedule(
            viewModel: viewModel,
            gate: gate,
            linkTarget: $linkTarget,
            createLinkTarget: $createLinkTarget,
            onExpandConnectedLogin: onExpandConnectedLogin
        )
    }
}