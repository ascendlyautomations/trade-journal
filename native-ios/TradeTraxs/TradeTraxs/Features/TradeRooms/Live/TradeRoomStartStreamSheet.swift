import SwiftUI

/// First step: method selection (OBS only on iOS).
struct TradeRoomStartStreamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    /// Single option, kept as a picker per product spec.
    @State private var method: String = "obs"
    @State private var streamTitle: String = ""

    var onConfirmOBS: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    streamingMethodSection
                    streamTitleSection
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startActionBar
            }
            .experienceScreenBackground(usesGroupedFillInLightMode: true)
            .navigationTitle("Start a stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .experienceSheetChrome(detents: [.large])
    }

    private var streamingMethodSection: some View {
        sectionBlock(title: "Streaming method") {
            Picker("Streaming method", selection: $method) {
                Text("OBS Studio").tag("obs")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tradingRulesInsetControl()

            Text("Other streaming methods are available on web.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var streamTitleSection: some View {
        sectionBlock(title: "Stream title") {
            TextField("e.g. Trading NY Session, NQ Futures", text: $streamTitle)
                .textInputAutocapitalization(.sentences)
                .tradingRulesInsetControl()
                .accessibilityIdentifier("tradeRooms.startStream.title")

            Text("\(streamTitle.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(TradeRoomBroadcastStreamTitle.maxLength)")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var startActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            ExperienceButton(
                title: "Start with OBS",
                kind: .primary,
                isEnabled: TradeRoomBroadcastStreamTitle.normalize(streamTitle) != nil
            ) {
                guard let title = TradeRoomBroadcastStreamTitle.normalize(streamTitle) else { return }
                onConfirmOBS(title)
            }
            .accessibilityIdentifier("tradeRooms.startStream.confirmOBS")
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .experienceChromeBarBackground()
        }
    }

    private func sectionBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                content()
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
        }
    }
}