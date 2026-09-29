import PhotosUI
import SwiftUI
import UIKit

enum UserSubmissionFormPhase: Equatable {
    case editing
    case submitting
    case succeeded
    case failed(String)
}

struct SubmissionScreenshotSection: View {
    @Binding var photoItem: PhotosPickerItem?
    @Binding var previewImage: UIImage?

    @Environment(\.themeColors) private var colors

    var body: some View {
        Section {
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                    .accessibilityLabel("Screenshot preview")

                HStack(spacing: ExperienceSpacing.sm) {
                    PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                        Text("Replace")
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    }
                    Button("Remove", role: .destructive) {
                        previewImage = nil
                        photoItem = nil
                    }
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(colors.accent)
                        Text("Add Screenshot")
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Screenshot")
        } footer: {
            Text("Optional. Helps us understand the issue.")
                .foregroundStyle(colors.tertiaryText)
        }
    }
}

struct SubmissionSuccessPanel: View {
    let title: String
    let message: String
    let onDone: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(colors.success)
            Text(title)
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(message)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(ExperienceSpacing.lg)
    }
}

struct SubmissionFailureBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(message)
                .experienceStyle(.footnote, color: colors.loss)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("Try again", action: onRetry)
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
        }
    }
}

extension UserSubmissionError {
    var displayMessage: String {
        switch self {
        case .notAuthenticated:
            return "Sign in to submit this form."
        case .validation(let message):
            return message
        case .screenshotUpload(let message):
            return message
        case .persistence(let message):
            return message
        }
    }
}

enum SubmissionPhotoLoading {
    static func loadUIImage(from item: PhotosPickerItem?) async -> UIImage? {
        guard let item else { return nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return nil }
        return image
    }
}
