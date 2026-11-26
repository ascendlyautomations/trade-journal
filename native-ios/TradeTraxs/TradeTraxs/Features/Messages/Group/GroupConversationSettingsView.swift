import PhotosUI
import SwiftUI
import UIKit

struct GroupConversationSettingsView: View {
    @State private var draftName: String
    @State private var photoItem: PhotosPickerItem?
    @State private var cropSourceImage: UIImage?
    @State private var avatarPreview: UIImage?
    @State private var pendingAvatarJPEG: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    let conversation: Conversation
    let imagePipeline: any ImagePipeline
    let onSave: (_ name: String?, _ avatarJPEG: Data?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(
        conversation: Conversation,
        imagePipeline: any ImagePipeline,
        onSave: @escaping (_ name: String?, _ avatarJPEG: Data?) async throws -> Void
    ) {
        self.conversation = conversation
        self.imagePipeline = imagePipeline
        self.onSave = onSave
        _draftName = State(initialValue: conversation.title ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: ExperienceSpacing.md) {
                        avatarControl
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text("Group Photo")
                                .experienceStyle(.footnote, color: colors.secondaryText)
                            Text(avatarPreview == nil && conversation.avatar == nil ? "Optional" : "Tap to change")
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                    .padding(.vertical, ExperienceSpacing.xxs)

                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text("Group Name")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                        TextField("Group name", text: $draftName)
                            .font(ExperienceTypography.body)
                            .foregroundStyle(colors.primaryText)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(false)
                            .padding(.horizontal, ExperienceSpacing.sm)
                            .padding(.vertical, ExperienceSpacing.xs)
                            .experienceFilterSearchField()
                            .accessibilityIdentifier("groupSettings.name")
                    }
                    .listRowInsets(EdgeInsets(
                        top: ExperienceSpacing.xs,
                        leading: ExperienceSpacing.md,
                        bottom: ExperienceSpacing.xs,
                        trailing: ExperienceSpacing.md
                    ))
                } header: {
                    Text("Group Details")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .experienceStyle(.caption, color: colors.error)
                    }
                }
            }
            .experiencePlainListStyle()
            .experienceScreenBackground()
            .experienceNavigationTitle("Group Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await presentAvatarCrop(for: item) }
            }
            .imageCropSelectionBaked(
                sourceImage: $cropSourceImage,
                preset: .avatar,
                onConfirm: { image in
                    avatarPreview = image
                    pendingAvatarJPEG = MediaImagePreparation.avatarJPEGData(from: image)
                    photoItem = nil
                    cropSourceImage = nil
                },
                onCancel: { photoItem = nil }
            )
            .accessibilityIdentifier("groupSettings.sheet")
        }
    }

    private var avatarControl: some View {
        PhotosPicker(
            selection: $photoItem,
            matching: MediaPickerPolicy.imageOnly.matching,
            preferredItemEncoding: .compatible
        ) {
            ZStack {
                if let avatarPreview {
                    Image(uiImage: avatarPreview)
                        .resizable()
                        .scaledToFill()
                } else {
                    GroupConversationAvatarView(
                        avatar: conversation.avatar,
                        imagePipeline: imagePipeline,
                        size: 56
                    )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                ExperienceIcon(icon: .photo, size: .xs, color: colors.onAccent)
                    .padding(4)
                    .background(colors.accent, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel("Change group photo")
        .accessibilityIdentifier("groupSettings.avatarPicker")
    }

    private func presentAvatarCrop(for item: PhotosPickerItem?) async {
        guard let image = await ImageCropSelectionSupport.loadUIImage(from: item) else { return }
        cropSourceImage = image
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingTitle = conversation.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name: String? = {
            if trimmed == existingTitle { return nil }
            return trimmed.isEmpty ? nil : trimmed
        }()
        guard name != nil || pendingAvatarJPEG != nil else {
            dismiss()
            return
        }
        do {
            try await onSave(name, pendingAvatarJPEG)
            dismiss()
        } catch {
            errorMessage = ConversationThreadSupport.message(for: error)
        }
    }
}