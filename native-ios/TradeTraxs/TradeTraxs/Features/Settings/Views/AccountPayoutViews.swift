import PhotosUI
import SwiftUI
import UIKit

/// Completed payout cycles from `account_payout_cycles` — funded prop-firm history.
struct FundedPayoutCycleHistoryContent: View {
    let cycles: [AccountPayoutCycle]

    @Environment(\.themeColors) private var colors

    var body: some View {
        if cycles.isEmpty {
            Text("No recorded payouts yet")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .padding(.top, ExperienceSpacing.xxs)
        } else {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(cycles) { cycle in
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        HStack {
                            if let amount = cycle.payoutAmount {
                                Text(TradeDisplay.pnlText(Money(amount: amount)))
                                    .experienceStyle(.body, color: colors.primaryText)
                            }
                            Spacer(minLength: 0)
                            if let endedAt = cycle.endedAt {
                                Text(TradeDisplay.dateText(endedAt))
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                        }
                        if let after = cycle.balanceAfterPayout {
                            Text("Balance after: \(DashboardViewModel.money(after))")
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                }
            }
            .padding(.top, ExperienceSpacing.xxs)
        }
    }
}

/// Owner-only manual payout rows — shared by Manage Accounts and Dashboard Payouts.
struct AccountPayoutListContent: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
    var addButtonTitle: String = "Add Payout"
    var onAdd: () -> Void
    var onEdit: (AccountPayoutEntry) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        if viewModel.isLoadingPayouts, viewModel.payoutEntries(for: accountID).isEmpty {
            HStack {
                ProgressView()
                Text("Loading payouts…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        } else if let payoutError = viewModel.payoutError,
                  viewModel.payoutEntries(for: accountID).isEmpty {
            SettingsInlineError(message: payoutError) {
                Task { await viewModel.loadPayoutEntries(for: accountID) }
            }
        } else {
            let rows = viewModel.payoutEntries(for: accountID)
            if rows.isEmpty {
                Text("No payout entries yet")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(rows) { entry in
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        HStack {
                            Text(TradeDisplay.pnlText(entry.amount))
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer(minLength: 0)
                            Text(TradeDisplay.dateText(entry.payoutDate))
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                        if let note = entry.note, !note.isEmpty {
                            Text(note)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { _ = await viewModel.deletePayout(entryID: entry.id, accountID: accountID) }
                        } label: {
                            Text("Delete")
                        }
                        Button {
                            onEdit(entry)
                        } label: {
                            Text("Edit")
                        }
                    }
                }
            }

            Button(action: onAdd) {
                Label(addButtonTitle, systemImage: "plus.circle")
            }
        }
    }
}

enum AccountPayoutEditorCopy: Sendable {
    case manageAccount
    case payoutHistory

    var addTitle: String {
        switch self {
        case .manageAccount: return "Add Payout"
        case .payoutHistory: return "Edit Payout"
        }
    }

    var editTitle: String { "Edit Payout" }

    var amountLabel: String { "Amount" }
    var dateLabel: String { "Payout Date" }
}

struct AccountPayoutEditorSheet: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
    let editingEntryID: AccountPayoutEntryID?
    @Binding var draft: AccountPayoutEntryDraft
    @Binding var isPresented: Bool
    var copy: AccountPayoutEditorCopy = .manageAccount
    /// When set with ``imageOwnerID``, the owner can add, replace, or remove the picture.
    var imageStorage: (any ObjectStorageProviding)? = nil
    var imageOwnerID: String? = nil

    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var removeImage = false
    @State private var localError: String?

    private var canEditImage: Bool {
        imageStorage != nil && imageOwnerID?.isEmpty == false && editingEntryID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                SettingsLabeledField(title: copy.amountLabel, helper: "USD") {
                    TextField("0", text: $draft.amountDigits.numericInput(.unsignedCurrency))
                        .keyboardType(.decimalPad)
                }
                DatePicker(copy.dateLabel, selection: $draft.payoutDate, displayedComponents: .date)
                SettingsLabeledField(title: "Note", helper: "Optional") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...3)
                }
                if canEditImage {
                    pictureSection
                }
                if let formError = localError ?? viewModel.formError, !formError.isEmpty {
                    SettingsInlineError(message: formError)
                }
            }
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle(
                editingEntryID == nil ? copy.addTitle : copy.editTitle
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .presentationDetents(canEditImage ? [.medium, .large] : [.medium])
        .experienceProtectedFormDismiss()
    }

    @ViewBuilder
    private var pictureSection: some View {
        Section {
            if let pendingImage, !removeImage {
                Image(uiImage: pendingImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !removeImage, let raw = draft.imageURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxHeight: 180)
            }
            PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                Label(showsExistingPicture ? "Replace Picture" : "Add Picture", systemImage: "photo")
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPickedPhoto(item) }
            }
            if showsExistingPicture {
                Button("Remove Picture", role: .destructive) {
                    pendingImage = nil
                    photoItem = nil
                    removeImage = true
                }
            }
        } header: {
            Text("Picture")
        }
    }

    private var showsExistingPicture: Bool {
        if removeImage { return false }
        if pendingImage != nil { return true }
        let trimmed = draft.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let image = await SubmissionPhotoLoading.loadUIImage(from: item) else { return }
        pendingImage = image
        removeImage = false
    }

    private func save() async {
        let previousImageURL = draft.imageURL
        var imageWrite: PayoutEntryImageWrite = .unchanged
        var uploadedURL: String?
        if canEditImage, let storage = imageStorage, let ownerID = imageOwnerID {
            if removeImage {
                imageWrite = .clear
            } else if let pendingImage {
                do {
                    uploadedURL = try await PayoutEntryImageUpload.uploadJPEG(
                        image: pendingImage,
                        userID: ownerID,
                        storage: storage
                    )
                    imageWrite = .set(uploadedURL ?? "")
                } catch {
                    localError = UserFacingError.message(for: error)
                    return
                }
            }
        }

        let succeeded: Bool
        if let editingEntryID {
            succeeded = await viewModel.updatePayout(
                entryID: editingEntryID,
                accountID: accountID,
                draft: draft,
                image: imageWrite
            )
        } else {
            succeeded = await viewModel.createPayout(accountID: accountID, draft: draft) != nil
        }

        if succeeded {
            if let storage = imageStorage, imageWrite != .unchanged {
                let savedURL: String? = {
                    switch imageWrite {
                    case .unchanged: return previousImageURL
                    case .set(let url): return url
                    case .clear: return nil
                    }
                }()
                let plan = PayoutImageReplacementPlan.succeeded(
                    previousURL: previousImageURL,
                    savedURL: savedURL
                )
                await OwnedMediaStorageCleanup.removePublicObjects(
                    urls: plan.deleteURLs,
                    storage: storage
                )
            }
            SaveSuccessConfirmationCenter.shared.present(SaveSuccessToastMessage.changesSaved)
            isPresented = false
        } else if let storage = imageStorage {
            let plan = PayoutImageReplacementPlan.failedSave(
                uploadedURL: uploadedURL,
                previousURL: previousImageURL
            )
            await OwnedMediaStorageCleanup.removePublicObjects(
                urls: plan.deleteURLs,
                storage: storage
            )
        }
    }
}

/// Which screenshot URL remains after a withdrawal image edit.
nonisolated struct PayoutImageReplacementPlan: Equatable, Sendable {
    var deleteURLs: [String]
    var retainedURL: String?

    static func failedSave(uploadedURL: String?, previousURL: String?) -> PayoutImageReplacementPlan {
        let uploaded = uploadedURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PayoutImageReplacementPlan(
            deleteURLs: uploaded.isEmpty ? [] : [uploaded],
            retainedURL: previousURL
        )
    }

    static func succeeded(previousURL: String?, savedURL: String?) -> PayoutImageReplacementPlan {
        let previous = previousURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let saved = savedURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let deletes = !previous.isEmpty && previous != saved ? [previous] : []
        return PayoutImageReplacementPlan(
            deleteURLs: deletes,
            retainedURL: saved.isEmpty ? nil : saved
        )
    }
}

/// Uploads a payout screenshot before the ledger row is updated.
nonisolated enum PayoutEntryImageUpload {
    static func uploadJPEG(
        image: UIImage,
        userID: String,
        storage: any ObjectStorageProviding
    ) async throws -> String {
        let data = await MainActor.run {
            MediaImagePreparation.chatJPEGData(from: image)
        }
        guard let data else {
            throw UserSubmissionError.screenshotUpload("Couldn't prepare that image.")
        }
        guard data.count <= SubmissionScreenshotUpload.maxImageBytes else {
            throw UserSubmissionError.screenshotUpload("Image must be 15 MB or smaller.")
        }
        let path = SubmissionScreenshotUpload.storageObjectPath(userID: userID, prefix: "payouts")
        _ = try await storage.upload(
            bucket: StorageBucket.screenshots.rawValue,
            path: path,
            data: data,
            contentType: "image/jpeg"
        )
        guard let url = storage.publicURL(bucket: StorageBucket.screenshots.rawValue, path: path) else {
            throw UserSubmissionError.screenshotUpload("Couldn't resolve screenshot URL.")
        }
        return url.absoluteString
    }
}
