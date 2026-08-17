import SwiftUI
import UIKit

struct SettingsAffiliateView: View {
    @State private var viewModel: SettingsAffiliateViewModel
    @State private var didCopyCode = false

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment) {
        _viewModel = State(
            initialValue: SettingsAffiliateViewModel(
                referrals: data.referrals,
                session: data.session
            )
        )
    }

    init(viewModel: SettingsAffiliateViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            Section {
                SettingsIntroBlock(
                    title: "Earn rewards by referring traders",
                    message: "Share your referral link below. Friends who join with your code help you earn rewards."
                )
            }

            Section {
                SettingsInfoRow(title: "Code", value: viewModel.referral?.code ?? "—")
                if let code = viewModel.referral?.code, !code.isEmpty {
                    Button {
                        UIPasteboard.general.string = code
                        didCopyCode = true
                        ExperienceHaptics.play(.success)
                    } label: {
                        SettingsPrimaryActionLabel(
                            title: didCopyCode ? "Copied" : "Copy Referral Code",
                            systemImage: didCopyCode ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.affiliate.copy")
                }
                if let link = viewModel.referralLink {
                    ShareLink(item: link) {
                        SettingsPrimaryActionLabel(
                            title: "Share Referral Link",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }
            } header: {
                Text("Your Referral")
            } footer: {
                Text("Share your link or code with other traders.")
            }

            Section {
                SettingsIntroBlock(
                    title: "More on the website",
                    message: "See your application status, earnings, and payouts on TradeTraxs.com."
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Referrals")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.affiliate")
    }
}
