import SwiftUI

struct DashboardEquityDrawdownSettingsSheet: View {
    let accountName: String
    @Binding var limitDigits: String
    @Binding var limitType: LivePersonalDrawdownType
    @Binding var floorCapDigits: String
    var isSaving: Bool
    var errorMessage: String?
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    private let currencyFieldHeight: CGFloat = 44
    private let currencyLabelRowHeight: CGFloat = 28

    private enum Field {
        case limit
        case floorCap
    }

    private var showsFloorCapField: Bool {
        limitType == .trailing
    }

    private let typeSwitchAnimation: Animation = .easeInOut(duration: 0.22)

    private var floorCapInfo: String {
        "The highest balance your trailing drawdown floor can reach. Once it hits this amount, the floor stops moving upward."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text("Drawdown floor")
                            .experienceStyle(.headline, color: colors.primaryText)
                        Text(accountName)
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                        Text(
                            "Personal drawdown for this Live account (informational floor on the equity curve). Leave blank to clear."
                        )
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: ExperienceSpacing.sm) {
                        ForEach(LivePersonalDrawdownType.allCases, id: \.self) { type in
                            Button {
                                withAnimation(typeSwitchAnimation) {
                                    limitType = type
                                    if type == .fixed, focusedField == .floorCap {
                                        focusedField = .limit
                                    }
                                }
                            } label: {
                                Text(type.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, ExperienceSpacing.sm)
                                    .background(
                                        limitType == type
                                            ? colors.accent.opacity(0.22)
                                            : colors.fillSecondary.opacity(0.35),
                                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                            .stroke(
                                                limitType == type ? colors.accent.opacity(0.55) : colors.border.opacity(0.35),
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.experiencePlain)
                            .disabled(isSaving)
                        }
                    }

                    Group {
                        if showsFloorCapField {
                            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                                currencyField(
                                    title: "Max drawdown limit",
                                    text: $limitDigits,
                                    field: .limit,
                                    accessibilityID: "dashboard.equityDrawdownSettings.limit",
                                    showsInfoPlaceholder: true
                                )

                                currencyField(
                                    title: "Drawdown floor cap",
                                    text: $floorCapDigits,
                                    field: .floorCap,
                                    accessibilityID: "dashboard.equityDrawdownSettings.floorCap",
                                    titleAccessory: {
                                        AnalyticsMetricInfoButton(
                                            title: "Drawdown floor cap",
                                            bodyText: floorCapInfo,
                                            accessibilityID: "dashboard.equityDrawdownSettings.floorCapInfo"
                                        )
                                    }
                                )
                            }
                        } else {
                            currencyField(
                                title: "Max drawdown limit",
                                text: $limitDigits,
                                field: .limit,
                                accessibilityID: "dashboard.equityDrawdownSettings.limit"
                            )
                        }
                    }
                    .animation(typeSwitchAnimation, value: limitType)

                    if let errorMessage {
                        Text(errorMessage)
                            .experienceStyle(.footnote, color: colors.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(ExperienceSpacing.md)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Equity curve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ExperienceIndeterminateProgress()
                    } else {
                        Button("Save", action: onSave)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .experienceSheetChrome()
        .accessibilityIdentifier("dashboard.equityDrawdownSettings")
    }

    @ViewBuilder
    private func currencyField(
        title: String,
        text: Binding<String>,
        field: Field,
        accessibilityID: String,
        showsInfoPlaceholder: Bool = false,
        @ViewBuilder titleAccessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsInfoPlaceholder {
                    Color.clear
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                titleAccessory()
            }
            .frame(height: currencyLabelRowHeight, alignment: .topLeading)

            TextField("$0", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .padding(.horizontal, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity)
                .frame(height: currencyFieldHeight)
                .background(currencyFieldBackground, in: currencyFieldShape)
                .overlay(currencyFieldShape.stroke(currencyFieldBorder, lineWidth: 1))
                .disabled(isSaving)
                .accessibilityIdentifier(accessibilityID)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var currencyFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
    }

    private var currencyFieldBackground: Color {
        if colorScheme == .light {
            return colors.fillSecondary.opacity(0.55)
        }
        return colors.fillSecondary.opacity(0.35)
    }

    private var currencyFieldBorder: Color {
        if colorScheme == .light {
            return colors.border.opacity(0.65)
        }
        return colors.border.opacity(0.35)
    }
}