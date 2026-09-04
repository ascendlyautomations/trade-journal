import SwiftUI

/// Shared content-detail identity header — Trade / Post / Clip / Achievement.
struct DetailIdentityHeader: View {
    let initials: String
    let avatar: Image?
    let displayName: String
    let username: String
    /// Optional second-line suffix after username (e.g. Trade account identity).
    var subtitle: String? = nil
    let dateText: String
    let isOwner: Bool
    var contentLink: DetailContentLink? = nil
    var ownerProfileID: ProfileID? = nil
    var shareText: String = "TradeTraxs"
    var editTitle: String = "Edit"
    var deleteTitle: String = "Delete"
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var accessibilityIdentifier: String = "detail.identity"

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var isSharePresented = false

    var body: some View {
        // Equal row spacing; menu overlaid so it does not inflate the name-row height.
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            ExperienceAvatar(
                initials: initials,
                image: avatar,
                size: 44
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)
                    .padding(.trailing, 28)

                HStack(spacing: 4) {
                    if !username.isEmpty {
                        Text(username)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text("·")
                            .experienceStyle(.footnote, color: colors.tertiaryText)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(subtitle)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .minimumScaleFactor(0.9)
                    }
                }

                Text(dateText)
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                DetailOverflowMenu(
                    isOwner: isOwner,
                    onShare: contentLink == nil ? nil : { isSharePresented = true },
                    onCopyLink: contentLink.map { link in
                        { DetailOverflowActions.copyLink(link) }
                    },
                    onReport: reportAction,
                    editTitle: editTitle,
                    deleteTitle: deleteTitle,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let url = contentLink?.url {
                DetailShareSheet(items: [shareText, url])
            } else {
                DetailShareSheet(items: [shareText])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var reportAction: (() -> Void)? {
        guard !isOwner,
              let contentLink,
              let ownerProfileID
        else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            appEnvironment.contentReportPresenter.present(
                ContentReportRequest(
                    target: contentLink.reportTarget(ownerID: ownerProfileID),
                    subjectTitle: contentLink.reportSubjectTitle,
                    blockUserOffer: ownerProfileID
                )
            )
        }
    }
}

private struct DetailShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
