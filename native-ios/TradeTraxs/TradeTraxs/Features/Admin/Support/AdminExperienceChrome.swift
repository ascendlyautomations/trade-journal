import SwiftUI

/// Admin utility flow — back control only in the navigation bar; page titles live in content.
enum AdminRoute: Hashable, Codable {
    case charts
    case users
    case userDetail(AdminUserSummary)
    case contentReports
    case contentReportDetail(AdminContentReportSnapshot)
    case inspectTrade(TradeID)
    case inspectPost(PostID)
    case inspectReel(ReelID)
    case inspectAchievement(AchievementID)
    case inspectProfile(ProfileID)
    case inspectRoom(RoomID)
    case support
    case supportTicketDetail(AdminSupportTicketSnapshot)
    case bugReports
    case bugReportDetail(AdminBugReportSnapshot)
    case productFeedback
    case productFeedbackDetail(AdminProductFeedbackSnapshot)
}

extension View {
    /// Hides the main tab bar and suppresses navigation bar titles for the Admin subtree.
    func adminExperienceChrome() -> some View {
        toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
    }

    /// Establishes semantic page background immediately for Admin pushes (avoids warm system flash).
    func adminExperienceRootBackground() -> some View {
        modifier(AdminExperienceRootBackgroundModifier())
    }

    /// Admin list rows — cool pressed highlight (no warm UITableView selection).
    func adminListRowInteraction() -> some View {
        buttonStyle(AdminPlainRowButtonStyle())
            .experienceDashboardListRow()
    }
}

private struct AdminExperienceRootBackgroundModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(colors.groupedBackground.ignoresSafeArea())
    }
}

private struct AdminPlainRowButtonStyle: ButtonStyle {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed, colorScheme == .dark {
                    colors.fillSecondary.opacity(0.22)
                } else if configuration.isPressed {
                    colors.fillSecondary.opacity(0.35)
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AdminInContentHeadingModifier: ViewModifier {
    let title: String
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.xs)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

extension View {
    func adminScreenHeading(_ title: String) -> some View {
        modifier(AdminInContentHeadingModifier(title: title))
    }
}
