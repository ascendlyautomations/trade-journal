import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class CreateAchievementViewModel {
    enum Phase: Equatable {
        case idle
        case ready
        case publishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var accounts: [TradingAccount] = []
    private(set) var isLoadingAccounts = false
    private(set) var formError: String?
    private(set) var isUploadingMedia = false
    private(set) var lockKind = false

    var kind: AchievementKind = .milestone
    var titleText = ""
    var descriptionText = ""
    var payoutAmountText = ""
    var achievedAt: Date = .now
    var isPublic = true
    var selectedAccountID: TradingAccountID?
    private(set) var finalImage: UIImage?
    private(set) var finalImageData: Data?

    private let achievements: any AchievementRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let uploadServices: GlobalUploadServices
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var hasPrepared = false
    private var hasLoadedAccounts = false

    init(
        achievements: any AchievementRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        uploadServices: GlobalUploadServices,
        prefill: CreateAchievementPrefill? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.achievements = achievements
        self.trades = trades
        self.session = session
        self.uploadServices = uploadServices
        self.onDismiss = onDismiss
        if let prefill {
            applyPrefill(prefill)
        }
    }

    var selectedAccount: TradingAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    var accountsForPicker: [TradingAccount] {
        let base = TradingAccountDropdownFilter.selectableForLinking(accounts)
        let resolved = OwnerAccountDropdownSupport.resolvedAccounts(
            profileID: viewerID,
            fallback: accounts
        )
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        return base.map { byID[$0.id] ?? $0 }
    }

    var ownerAccountsProfileID: ProfileID? { viewerID }

    var isPayoutKind: Bool {
        switch kind {
        case .propFirmPayout, .liveTradingPayout: return true
        case .passedEvaluation, .milestone: return false
        }
    }

    /// Screenshot/proof required for payout and evaluation; optional for milestone.
    var isProofRequired: Bool {
        switch kind {
        case .milestone: return false
        case .propFirmPayout, .liveTradingPayout, .passedEvaluation: return true
        }
    }

    var kindTitle: String {
        Self.displayTitle(for: kind)
    }

    var hasUnsavedChanges: Bool {
        !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !payoutAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || finalImageData != nil
            || selectedAccountID != nil
            || kind != .milestone
            || !isPublic
    }

    var canPublish: Bool {
        phase == .ready && isFormCompleteForSubmit
    }

    /// Mirrors ``validate()`` without mutating ``formError`` — drives submit button state.
    var isFormCompleteForSubmit: Bool {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        if isProofRequired, finalImageData == nil { return false }
        if isPayoutKind {
            guard let amount = Self.parsePayout(payoutAmountText), amount > 0 else { return false }
        }
        guard achievedAt <= Date().addingTimeInterval(60) else { return false }
        return true
    }

    static let allKinds: [AchievementKind] = [
        .propFirmPayout,
        .liveTradingPayout,
        .passedEvaluation,
        .milestone,
    ]

    static func displayTitle(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Evaluation"
        case .milestone: return "Milestone"
        }
    }

    func loadIfNeeded() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { await prepare() }
    }

    func retryLoad() {
        hasPrepared = false
        loadIfNeeded()
    }

    func loadAccountsIfNeeded() {
        guard !hasLoadedAccounts else { return }
        hasLoadedAccounts = true
        Task { await loadAccounts() }
    }

    func selectKind(_ kind: AchievementKind) {
        ExperienceHaptics.play(.selection)
        self.kind = kind
        formError = nil
    }

    func selectAccount(_ id: TradingAccountID?) {
        ExperienceHaptics.play(.selection)
        selectedAccountID = id
    }

    func setImage(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        finalImage = applied.finalImage
        finalImageData = applied.uploadData
    }

    func setImage(_ image: UIImage?) {
        guard let image else {
            clearImage()
            return
        }
        let pixelSize = MediaImageOrientation.pixelSize(of: image)
        setImage(
            ImageCropSelectionResult(
                image: image,
                aspectMode: .original,
                sourcePixelSize: pixelSize
            )
        )
    }

    func clearImage() {
        finalImageData = nil
        finalImage = nil
    }

    #if DEBUG
    func applyScreenshotImageFixture() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        }
        setImage(image)
    }
    #endif

    func publish() {
        guard phase == .ready else { return }
        formError = nil
        guard validate() else { return }
        guard let viewerID else {
            formError = "Sign in to create an achievement."
            return
        }
        if isProofRequired, finalImageData == nil {
            formError = "An image is required."
            return
        }

        if let finalImage, let finalImageData {
            PostImageUploadProbe.log(finalImage: finalImage, uploadData: finalImageData)
        }

        let payout = isPayoutKind ? Self.parsePayout(payoutAmountText) : nil
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = AchievementUploadSpec(
            jobID: UUID().uuidString,
            authorID: viewerID,
            kind: kind,
            title: trimmedTitle,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            payout: payout,
            payoutText: payout.map { Self.formatPayoutText($0) },
            firm: firmForSelectedAccount(),
            accountID: selectedAccountID,
            imageData: finalImageData,
            isPublic: isPublic,
            achievedAt: achievedAt
        )
        let jobID = GlobalUploadCoordinator.shared.enqueueAchievement(spec: spec, services: uploadServices)
        clearImage()
        titleText = ""
        descriptionText = ""
        payoutAmountText = ""
        phase = .ready
        onDismiss()
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .achievement,
            event: .composerDismissed,
            taskCancelled: Task.isCancelled
        )
    }

    func dismissRequested() {
        onDismiss()
    }

    // MARK: - Private

    private func prepare() async {
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
        guard viewerID != nil else {
            phase = .failed("Sign in to create an achievement.")
            return
        }
        phase = .ready
    }

    func applyPrefill(_ prefill: CreateAchievementPrefill) {
        kind = prefill.kind
        titleText = prefill.titleText
        descriptionText = prefill.descriptionText
        payoutAmountText = prefill.payoutAmountText
        achievedAt = prefill.achievedAt
        selectedAccountID = prefill.selectedAccountID
        isPublic = prefill.isPublic
        lockKind = prefill.lockKind
    }

    private func loadAccounts() async {
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }
        guard let viewerID else { return }

        if viewerID.rawValue.hasPrefix("dev.") {
            accounts = CreateAchievementFixtures.accounts(owner: viewerID)
            return
        }

        do {
            accounts = try await SessionAccountsStore.shared.accounts(
                for: viewerID,
                repository: trades,
                requiresFullOwnerSnapshot: true
            )
        } catch {
            accounts = SessionAccountsStore.shared.cached(for: viewerID) ?? []
        }
    }

    private func validate() -> Bool {
        var missing: [String] = []
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { missing.append("Title") }
        if isPayoutKind, payoutAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Payout Amount")
        }
        if isProofRequired, finalImageData == nil { missing.append("Image") }

        if !missing.isEmpty {
            formError = "Please complete: \(missing.joined(separator: ", "))."
            return false
        }

        if isPayoutKind {
            guard let amount = Self.parsePayout(payoutAmountText), amount > 0 else {
                formError = "Please enter a valid payout amount."
                return false
            }
        }

        if achievedAt > Date().addingTimeInterval(60) {
            formError = "Achievement date can't be in the future."
            return false
        }

        return true
    }

    private func firmForSelectedAccount() -> String? {
        guard let account = selectedAccount else { return nil }
        if kind == .propFirmPayout || account.isPropFirmAccount {
            return account.name
        }
        return nil
    }

    private static func parsePayout(_ raw: String) -> Decimal? {
        NumericInputFieldSupport.parse(raw, style: .unsignedCurrency)
    }

    private static func formatPayoutText(_ amount: Decimal) -> String {
        NumberDisplay.currency(amount.abs, minimumFractionDigits: 0, maximumFractionDigits: 2, explicitPlus: true)
    }
}

private extension Decimal {
    var abs: Decimal { self < 0 ? -self : self }
}
