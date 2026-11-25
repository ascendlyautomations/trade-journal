import PhotosUI
import SwiftUI

struct ContactSupportFormView: View {
    let repository: any UserSubmissionRepository

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var topic: SupportContactTopic = .account
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshotPreview: UIImage?
    @State private var phase: UserSubmissionFormPhase = .editing

    var body: some View {
        Group {
            switch phase {
            case .succeeded:
                SubmissionSuccessPanel(
                    title: "Request submitted",
                    message: "Your support request was submitted. We will review it as soon as possible."
                ) {
                    dismiss()
                }
            default:
                formContent
            }
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Help & Support")
        .scrollDismissesKeyboard(.interactively)
        .experienceKeyboardDismissOnTapOutside()
        .onChange(of: photoItem) { _, item in
            Task {
                screenshotPreview = await SubmissionPhotoLoading.loadUIImage(from: item)
            }
        }
        .accessibilityIdentifier("settings.support.contact")
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if case .failed(let error) = phase {
                    SubmissionFailureBanner(message: error) {
                        phase = .editing
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .experienceGroupedPanel(cornerRadius: ExperienceRadius.md, prominence: .standard)
                }

                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("How can we help?")
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text("Choose a subject and tell us what you need. We typically respond by email.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                unifiedMessageCard

                screenshotCard

                ExperienceButton(
                    title: "Submit",
                    kind: .primary,
                    isEnabled: canSubmit,
                    isLoading: phase == .submitting,
                    accessibilityIdentifier: "settings.support.submit"
                ) {
                    Task { await submit() }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private var unifiedMessageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                supportFieldLabel("Subject")
                Picker("Subject", selection: $topic) {
                    ForEach(SupportContactTopic.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(colors.accent)
                .font(ExperienceTypography.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Subject")
                .accessibilityValue(topic.label)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)

            Divider()
                .overlay(colors.separator)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                supportFieldLabel("Message")
                TextField(
                    "Describe what happened and what you need.",
                    text: $message,
                    axis: .vertical
                )
                .lineLimit(4 ... 10)
                .textFieldStyle(.plain)
                .font(ExperienceTypography.subheadline)
                .foregroundStyle(colors.primaryText)
                .padding(ExperienceSpacing.xs)
                .frame(minHeight: 72, alignment: .topLeading)
                .background(supportInsetFieldBackground)
                .accessibilityLabel("Message")
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceGroupedPanel(cornerRadius: ExperienceRadius.md, prominence: .standard)
    }

    private var supportInsetFieldBackground: some View {
        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            .fill(colors.fillSecondary.opacity(0.65))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    .strokeBorder(colors.border.opacity(0.55), lineWidth: ExperienceBorder.hairline)
            }
    }

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            supportFieldLabel("Screenshot")
            Text("Optional. Helps us understand the issue.")
                .font(ExperienceTypography.caption)
                .foregroundStyle(colors.tertiaryText)

            if let image = screenshotPreview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                    .accessibilityLabel("Screenshot preview")

                HStack(spacing: ExperienceSpacing.md) {
                    PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                        Text("Replace")
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    }
                    Button("Remove", role: .destructive) {
                        screenshotPreview = nil
                        photoItem = nil
                    }
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: "photo.badge.plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.accent)
                        Text("Add Screenshot")
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer()
                        ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.tertiaryText)
                    }
                    .padding(ExperienceSpacing.xs)
                    .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    .background {
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .fill(colors.fillSecondary.opacity(0.45))
                            .overlay {
                                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                    .strokeBorder(colors.border.opacity(0.55), lineWidth: ExperienceBorder.hairline)
                            }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                }
                .buttonStyle(.experiencePlain)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceGroupedPanel(cornerRadius: ExperienceRadius.md, prominence: .standard)
    }

    private func supportFieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ExperienceTypography.caption.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .tracking(0.4)
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard canSubmit, phase != .submitting else { return }
        phase = .submitting
        do {
            try await repository.submitSupportTicket(
                SupportTicketSubmission(
                    category: topic.ticketCategory,
                    subject: topic.ticketSubject,
                    message: message,
                    screenshot: screenshotPreview
                )
            )
            phase = .succeeded
        } catch let error as UserSubmissionError {
            phase = .failed(error.displayMessage)
        } catch {
            phase = .failed("Couldn't submit your request. Please try again.")
        }
    }
}