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

    var kind: AchievementKind = .milestone
    var titleText = ""
    var descriptionText = ""
    var payoutAmountText = ""
    var achievedAt: Date = .now
    var isPublic = true
    var selectedAccountID: TradingAccountID?
    var imageData: Data?
    var imagePreview: UIImage?

    private let achievements: any AchievementRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false
    private var hasLoadedAccounts = false

    init(
        achievements: any AchievementRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onDismiss: @escaping () -> Void
    ) {
        self.achievements = achievements
        self.trades = trades
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.onDismiss = onDismiss
    }

    var selectedAccount: TradingAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    var isPayoutKind: Bool {
        switch kind {
        case .propFirmPayout, .liveTradingPayout: return true
        case .passedEvaluation, .milestone: return false
        }
    }

    var kindTitle: String {
        Self.displayTitle(for: kind)
    }

    var hasUnsavedChanges: Bool {
        !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !payoutAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || imageData != nil
            || selectedAccountID != nil
            || kind != .milestone
            || !isPublic
    }

    var canPublish: Bool {
        phase != .publishing && phase != .idle
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

    func setImage(_ image: UIImage?) {
        guard let image else {
            imageData = nil
            imagePreview = nil
            return
        }
        imagePreview = image
        imageData = MediaImagePreparation.jpegData(from: image)
    }

    func clearImage() {
        imageData = nil
        imagePreview = nil
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
        guard canPublish, publishTask == nil else { return }
        publishTask = Task { await performPublish() }
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
                repository: trades
            )
        } catch {
            accounts = SessionAccountsStore.shared.cached(for: viewerID) ?? []
        }
    }

    private func performPublish() async {
        formError = nil
        guard validate() else {
            publishTask = nil
            return
        }
        guard let viewerID else {
            formError = "Sign in to create an achievement."
            publishTask = nil
            return
        }
        guard let imageData else {
            formError = "An image is required."
            publishTask = nil
            return
        }

        phase = .publishing
        var uploadedStoragePath: String?
        do {
            let payout = isPayoutKind ? Self.parsePayout(payoutAmountText) : nil
            let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

            let imageRef: MediaReference
            if viewerID.rawValue.hasPrefix("dev.") {
                imageRef = MediaReference(id: "dev/create-achievement.jpg", kind: .image, altText: nil)
            } else {
                isUploadingMedia = true
                let uploaded = try await uploadImage(imageData, viewerID: viewerID)
                uploadedStoragePath = uploaded.storagePath
                imageRef = MediaReference(id: uploaded.publicURL, kind: .image, altText: nil)
                isUploadingMedia = false
            }

            let draft = Achievement(
                id: AchievementID("pending"),
                ownerProfileID: viewerID,
                kind: kind,
                title: trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                tier: .bronze,
                value: payout.map { Money(amount: $0) },
                valueText: payout.map { Self.formatPayoutText($0) },
                firm: firmForSelectedAccount(),
                accountID: selectedAccountID,
                image: imageRef,
                isPublic: isPublic,
                isFeatured: false,
                sortOrder: 0,
                achievedAt: achievedAt
            )

            let saved: Achievement
            if viewerID.rawValue.hasPrefix("dev.") {
                var fixture = CreateAchievementFixtures.sampleAchievement(
                    owner: viewerID,
                    kind: kind,
                    title: trimmedTitle
                )
                fixture.description = draft.description
                fixture.value = draft.value
                fixture.valueText = draft.valueText
                fixture.firm = draft.firm
                fixture.accountID = draft.accountID
                fixture.image = draft.image
                fixture.isPublic = draft.isPublic
                fixture.achievedAt = draft.achievedAt
                saved = fixture
            } else {
                saved = try await achievements.save(draft)
            }

            OwnerProfileOptimisticStore.shared.noteAchievementCreated(saved)
            ExperienceHaptics.play(.achievement)
            phase = .ready
            onDismiss()
        } catch {
            isUploadingMedia = false
            if let path = uploadedStoragePath {
                try? await objectStorage.delete(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: path
                )
            }
            phase = .ready
            formError = "Couldn't publish achievement. Check your connection and try again."
        }
        publishTask = nil
    }

    private func validate() -> Bool {
        var missing: [String] = []
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { missing.append("Title") }
        if isPayoutKind, payoutAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Payout Amount")
        }
        if imageData == nil { missing.append("Image") }

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

    private struct UploadedImage {
        var storagePath: String
        var publicURL: String
    }

    private func uploadImage(_ data: Data, viewerID: ProfileID) async throws -> UploadedImage {
        let path = "achievements/\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.screenshots.rawValue,
                path: path,
                data: data,
                contentType: "image/jpeg",
                purpose: .postImage
            )
        )
        let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.screenshots.rawValue,
            path: reference.id
        )?.absoluteString ?? reference.id
        return UploadedImage(storagePath: reference.id, publicURL: publicURL)
    }

    private static func parsePayout(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        return DecimalParser.parse(cleaned)
    }

    private static func formatPayoutText(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount.abs)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let formatted = formatter.string(from: number) ?? "\(number)"
        return "+$\(formatted)"
    }
}

private extension Decimal {
    var abs: Decimal { self < 0 ? -self : self }
}
