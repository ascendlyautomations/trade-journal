import Foundation
import Observation

@Observable
@MainActor
final class BrokerImportFlowModel {
    enum Phase: Equatable {
        case idle
        case running(BrokerImportProgressSnapshot)
        case awaitingTradovateConfirmation([TradovateImportPreviewTrade])
        case success(newCount: Int, tradeIDs: [TradeID])
        case upToDate
        case failed(message: String, action: BrokerImportFailureAction)
    }

    enum BrokerImportFailureAction: Equatable {
        case retry
        case syncInProgress
        case reconnect
        case dismiss
    }

    struct BrokerImportProgressSnapshot: Equatable {
        var accountTitle: String
        var accountSubtitle: String
        var stage: BrokerImportProgressStage
        var progress: Double
        var processedCaption: String?
    }

    private(set) var phase: Phase = .idle
    private(set) var isPersistingTradovateImport = false
    private(set) var pendingRithmicPasswordTarget: BrokerImportEligibilityTarget?
    var isPresented = false

    private var activeTarget: BrokerImportEligibilityTarget?
    private var pendingTradovateConnectionId: String?
    private var pendingTradovateMappingId: String?
    private var stageAnimationTask: Task<Void, Never>?
    private var data: DataEnvironment?

    func startImport(
        target: BrokerImportEligibilityTarget,
        data: DataEnvironment,
        rithmicPassword: String? = nil
    ) {
        self.data = data
        activeTarget = target
        pendingTradovateConnectionId = nil
        pendingTradovateMappingId = nil
        pendingRithmicPasswordTarget = nil
        isPresented = true
        Task { await runImport(target: target, rithmicPassword: rithmicPassword) }
    }

    func retryImport() {
        guard let target = activeTarget, data != nil else { return }
        Task { await runImport(target: target, rithmicPassword: nil) }
    }

    func confirmTradovateImport() {
        guard let data,
              let connectionId = pendingTradovateConnectionId,
              let mappingId = pendingTradovateMappingId,
              let target = activeTarget
        else { return }
        Task {
            await runTradovatePersistImport(
                data: data,
                target: target,
                connectionId: connectionId,
                mappingId: mappingId
            )
        }
    }

    func cancelTradovateConfirmation() {
        if let data,
           let connectionId = pendingTradovateConnectionId,
           let mappingId = pendingTradovateMappingId
        {
            Task {
                _ = try? await data.brokerIntegrations.syncTradovateAccount(
                    connectionId: connectionId,
                    mappingId: mappingId,
                    mode: .cancelPreview
                )
            }
        }
        close(reset: true)
    }

    func close(reset: Bool) {
        stageAnimationTask?.cancel()
        stageAnimationTask = nil
        isPresented = false
        if reset {
            phase = .idle
            activeTarget = nil
            pendingTradovateConnectionId = nil
            pendingTradovateMappingId = nil
        }
    }

    // MARK: - Import execution

    private func runImport(
        target: BrokerImportEligibilityTarget,
        rithmicPassword: String?
    ) async {
        guard let data else { return }
        let presentation = presentationLines(for: target)
        beginRunning(
            accountTitle: presentation.title,
            accountSubtitle: presentation.subtitle,
            stage: .connecting,
            progress: 0.02
        )

        do {
            switch target.provider {
            case .tradovate:
                await runTradovatePreviewImport(data: data, target: target)
            case .rithmic:
                let response = try await performSyncWithIndeterminateProgress(
                    accountTitle: presentation.title,
                    accountSubtitle: presentation.subtitle,
                    previewCount: nil
                ) {
                    try await data.brokerIntegrations.syncRithmicAccount(
                        connectionId: target.connectionId,
                        mappingId: target.mappingId,
                        password: rithmicPassword
                    )
                }
                BrokerSyncDebugLog.syncReport(
                    provider: .rithmic,
                    connectionID: target.connectionId,
                    accountMappingID: target.mappingId,
                    response: response
                )
                await finishWithSyncResponse(response, target: target, data: data)
            }
        } catch {
            fail(BrokerSyncPresentation.temporaryFailureMessage(), action: .retry)
        }
    }

    func reconnectFromFailure() {
        guard let target = activeTarget, let data else { return }
        switch target.provider {
        case .rithmic:
            pendingRithmicPasswordTarget = target
            isPresented = false
            phase = .idle
        case .tradovate:
            Task { await reconnectTradovate(data: data, target: target) }
        }
    }

    private func reconnectTradovate(
        data: DataEnvironment,
        target: BrokerImportEligibilityTarget
    ) async {
        let presentation = presentationLines(for: target)
        beginRunning(
            accountTitle: presentation.title,
            accountSubtitle: presentation.subtitle,
            stage: .connecting,
            progress: 0.02
        )
        let outcome = await BrokerTradovateReconnectImport.reconnectAndSync(
            broker: data.brokerIntegrations,
            connectionId: target.connectionId,
            mappingId: target.mappingId
        )
        switch outcome {
        case .cancelled:
            fail(
                BrokerSyncPresentation.reconnectRequiredMessage(provider: .tradovate),
                action: .reconnect
            )
        case .oauthFailed:
            fail(
                BrokerSyncPresentation.reconnectRequiredMessage(provider: .tradovate),
                action: .reconnect
            )
        case .syncCompleted(let response):
            await finishWithSyncResponse(response, target: target, data: data)
        }
    }

    private func runTradovatePreviewImport(
        data: DataEnvironment,
        target: BrokerImportEligibilityTarget
    ) async {
        let presentation = presentationLines(for: target)
        do {
            let preview = try await performSyncWithIndeterminateProgress(
                accountTitle: presentation.title,
                accountSubtitle: presentation.subtitle,
                previewCount: nil
            ) {
                try await data.brokerIntegrations.syncTradovateAccount(
                    connectionId: target.connectionId,
                    mappingId: target.mappingId,
                    mode: .preview
                )
            }
            BrokerSyncDebugLog.syncReport(
                provider: .tradovate,
                connectionID: target.connectionId,
                accountMappingID: target.mappingId,
                response: preview
            )
            guard preview.summary.ok else {
                await handleSyncFailure(preview, target: target)
                return
            }
            let previews = preview.summary.importPreviewTrades
            if previews.isEmpty {
                setProgress(stage: .finalizing, progress: 1, processedCaption: nil)
                try await Task.sleep(nanoseconds: 350_000_000)
                phase = .upToDate
                return
            }
            pendingTradovateConnectionId = target.connectionId
            pendingTradovateMappingId = target.mappingId
            phase = .awaitingTradovateConfirmation(previews)
        } catch {
            fail(BrokerSyncPresentation.temporaryFailureMessage(), action: .retry)
        }
    }

    private func runTradovatePersistImport(
        data: DataEnvironment,
        target: BrokerImportEligibilityTarget,
        connectionId: String,
        mappingId: String
    ) async {
        let presentation = presentationLines(for: target)
        isPersistingTradovateImport = true
        defer { isPersistingTradovateImport = false }
        beginRunning(
            accountTitle: presentation.title,
            accountSubtitle: presentation.subtitle,
            stage: .savingTrades,
            progress: 0.55,
            processedCaption: nil
        )
        do {
            let response = try await performSyncWithIndeterminateProgress(
                accountTitle: presentation.title,
                accountSubtitle: presentation.subtitle,
                previewCount: nil,
                lowerBound: 0.55
            ) {
                try await data.brokerIntegrations.syncTradovateAccount(
                    connectionId: connectionId,
                    mappingId: mappingId,
                    mode: .import
                )
            }
            BrokerSyncDebugLog.syncReport(
                provider: .tradovate,
                connectionID: connectionId,
                accountMappingID: mappingId,
                response: response
            )
            pendingTradovateConnectionId = nil
            pendingTradovateMappingId = nil
            await finishWithSyncResponse(response, target: target, data: data)
        } catch {
            fail(BrokerSyncPresentation.temporaryFailureMessage(), action: .retry)
        }
    }

    private func finishWithSyncResponse(
        _ response: TradovateAccountSyncResponse,
        target: BrokerImportEligibilityTarget,
        data: DataEnvironment
    ) async {
        guard response.summary.ok else {
            await handleSyncFailure(response, target: target)
            return
        }
        setProgress(stage: .finalizing, progress: 0.94, processedCaption: nil)
        guard let userID = await data.session.currentUserID else {
            fail(BrokerSyncPresentation.temporaryFailureMessage(), action: .retry)
            return
        }
        let owner = ProfileID(userID.rawValue)
        let reconciliation = await BrokerImportReconciliation.apply(
            owner: owner,
            summary: response.summary,
            tradesRepository: data.trades,
            detailCache: data.detailCache
        )
        let count = reconciliation.authoritativeNewCount
        if count == 0 {
            setProgress(stage: .finalizing, progress: 1, processedCaption: nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            phase = .upToDate
            return
        }
        setProgress(stage: .finalizing, progress: 1, processedCaption: nil)
        try? await Task.sleep(nanoseconds: 400_000_000)
        phase = .success(newCount: count, tradeIDs: reconciliation.newTradeIDs)
    }

    private func handleSyncFailure(
        _ response: TradovateAccountSyncResponse,
        target: BrokerImportEligibilityTarget
    ) async {
        let resolution = BrokerSyncFailureResolution.from(response)
        let action: BrokerImportFailureAction
        switch resolution {
        case .success:
            action = .dismiss
        case .reconnectRequired:
            action = .reconnect
        case .retryable:
            action = BrokerSyncFailureResolution.isSyncInProgress(response) ? .syncInProgress : .retry
        case .importFailed:
            action = .dismiss
        }
        fail(
            BrokerSyncPresentation.message(
                for: response,
                provider: target.provider,
                resolution: resolution
            ),
            action: action
        )
    }

    // MARK: - Progress animation

    private func performSyncWithIndeterminateProgress(
        accountTitle: String,
        accountSubtitle: String,
        previewCount: Int?,
        lowerBound: Double = 0.02,
        operation: () async throws -> TradovateAccountSyncResponse
    ) async throws -> TradovateAccountSyncResponse {
        stageAnimationTask?.cancel()
        let stages = BrokerImportProgressStage.allCases
        stageAnimationTask = Task {
            for stage in stages {
                guard !Task.isCancelled else { return }
                let cap = max(lowerBound, stage.indeterminateProgressCap)
                await MainActor.run {
                    setProgress(
                        stage: stage,
                        progress: cap,
                        processedCaption: processedCaption(previewCount: previewCount, stage: stage)
                    )
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
        defer { stageAnimationTask?.cancel() }
        return try await operation()
    }

    private func processedCaption(previewCount: Int?, stage: BrokerImportProgressStage) -> String? {
        guard let previewCount, previewCount > 0, stage == .processingTrades || stage == .savingTrades else {
            return nil
        }
        return "0 of \(previewCount) trades processed"
    }

    private func beginRunning(
        accountTitle: String,
        accountSubtitle: String,
        stage: BrokerImportProgressStage,
        progress: Double,
        processedCaption: String? = nil
    ) {
        phase = .running(
            BrokerImportProgressSnapshot(
                accountTitle: accountTitle,
                accountSubtitle: accountSubtitle,
                stage: stage,
                progress: progress,
                processedCaption: processedCaption
            )
        )
    }

    private func setProgress(
        stage: BrokerImportProgressStage,
        progress: Double,
        processedCaption: String?
    ) {
        guard case .running(let snap) = phase else { return }
        phase = .running(
            BrokerImportProgressSnapshot(
                accountTitle: snap.accountTitle,
                accountSubtitle: snap.accountSubtitle,
                stage: stage,
                progress: min(max(progress, 0), 1),
                processedCaption: processedCaption
            )
        )
    }

    private func fail(_ message: String, action: BrokerImportFailureAction) {
        stageAnimationTask?.cancel()
        phase = .failed(message: message, action: action)
    }

    private func presentationLines(for target: BrokerImportEligibilityTarget) -> (title: String, subtitle: String) {
        let provider = BrokerIntegrationDisplay.providerLabel(target.provider)
        let name = target.brokerAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = target.tradetraxsAccountName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let subtitle, !subtitle.isEmpty {
            return ("\(provider) · \(name)", "TradeTraxs account · \(subtitle)")
        }
        return ("\(provider) · \(name)", "Linked broker account")
    }
}
