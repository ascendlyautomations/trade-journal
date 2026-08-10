import SwiftUI

struct SettingsAffiliateView: View {
    @State private var viewModel: SettingsAffiliateViewModel

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

            Section("Referral") {
                SettingsInfoRow(title: "Code", value: viewModel.referral?.code ?? "—")
                if let link = viewModel.referralLink {
                    ShareLink(item: link) {
                        SettingsNavigationRow(title: "Share referral link", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Text("Affiliate application status, earnings ledger, and Stripe Connect payouts remain on the web Affiliate dashboard.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } header: {
                Text("Affiliate")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .navigationTitle("Referrals")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.affiliate")
    }
}
