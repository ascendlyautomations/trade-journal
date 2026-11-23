import SwiftUI

struct AdminChartsView: View {
    let data: DataEnvironment

    @State private var viewModel: AdminChartsViewModel

    init(data: DataEnvironment) {
        self.data = data
        _viewModel = State(initialValue: AdminChartsViewModel(repository: data.adminUsageAnalytics))
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(AdminChartsRange.allCases) { range in
                        Text(range.menuLabel).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, ExperienceSpacing.md)
                .onChange(of: viewModel.selectedRange) { _, _ in
                    Task { await viewModel.onRangeChanged() }
                }

                if viewModel.isLoading, viewModel.bundle == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, ExperienceSpacing.xl)
                } else if viewModel.bundle == nil, viewModel.productBundle == nil,
                          let error = viewModel.errorMessage ?? viewModel.productErrorMessage {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.load(force: true) }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                } else {
                    if let bundle = viewModel.bundle, let summary = viewModel.summary {
                        summaryGrid(summary, bundle: bundle)
                    } else if let error = viewModel.errorMessage {
                        productAnalyticsUnavailable(error)
                    }
                    if let product = viewModel.productBundle {
                        if let note = viewModel.productSeriesClampedNote {
                            Text(note)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                                .padding(.horizontal, ExperienceSpacing.md)
                        }
                        productOverviewSection(product)
                        productCharts(product)
                        productFeaturesTable(product)
                    } else if let productError = viewModel.productErrorMessage {
                        productAnalyticsUnavailable(productError)
                    }
                    lifecycleAnalyticsSection
                    historicalEngagementSection
                    if let bundle = viewModel.bundle {
                        charts(bundle)
                    }
                }
            }
            .padding(.bottom, ExperienceSpacing.xl)
        }
        .adminScreenHeading("Charts")
        .accessibilityIdentifier("admin.charts")
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func summaryGrid(_ summary: AdminChartsSummary, bundle: AdminUsageAnalyticsBundle) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: ExperienceSpacing.sm
        ) {
            summaryCard("DAU (latest day)", NumberDisplay.integer(summary.latestDailyActiveUsers))
            summaryCard("DAU (24h roll)", NumberDisplay.integer(summary.rollingDailyActiveUsers))
            summaryCard("New users", NumberDisplay.integer(summary.newUsersInPeriod))
            summaryCard("Trades", NumberDisplay.integer(summary.tradesInPeriod))
            summaryCard("Posts", NumberDisplay.integer(summary.postsInPeriod))
            summaryCard("Avg trades/day", NumberDisplay.decimal(summary.averageTradesPerDay, minimumFractionDigits: 1, maximumFractionDigits: 1))
            summaryCard("Avg posts/day", NumberDisplay.decimal(summary.averagePostsPerDay, minimumFractionDigits: 1, maximumFractionDigits: 1))
            summaryCard("Total users", NumberDisplay.integer(bundle.totalUsers))
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func summaryCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.tertiaryText)
            Text(value)
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.md)
        .experienceFloatingPanelBackground(
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
    }

    private func productAnalyticsUnavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Product analytics")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(message)
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    @ViewBuilder
    private func productOverviewSection(_ product: AdminProductAnalyticsBundle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Product engagement")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)
            if !product.meta.notes.isEmpty {
                Text(product.meta.notes.joined(separator: " "))
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: ExperienceSpacing.sm
            ) {
                summaryCard("Product DAU", metricLabel(product.overview.productDau))
                summaryCard("Product WAU", metricLabel(product.overview.productWau))
                summaryCard("Product MAU", metricLabel(product.overview.productMau))
                summaryCard("DAU/MAU", ratioLabel(product.overview.dauMauRatio))
                summaryCard(
                    "Retention D1",
                    retentionLabel(
                        rate: product.retentionD1Rate,
                        mature: product.retentionD1MatureCohortSize,
                        insufficient: product.retentionInsufficientData
                    )
                )
                summaryCard(
                    "Retention D7",
                    retentionLabel(
                        rate: product.retentionD7Rate,
                        mature: product.retentionD7MatureCohortSize,
                        insufficient: product.retentionInsufficientData
                    )
                )
                summaryCard(
                    "Retention D30",
                    retentionLabel(
                        rate: product.retentionD30Rate,
                        mature: product.retentionD30MatureCohortSize,
                        insufficient: product.retentionInsufficientData
                    )
                )
            }
            .padding(.horizontal, ExperienceSpacing.md)
        }
    }

    @ViewBuilder
    private func productCharts(_ product: AdminProductAnalyticsBundle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            AdminUsageLineChartSection(
                title: "Product active users / day",
                subtitle: AdminProductAnalyticsDefinition.productDau,
                points: AdminProductAnalyticsParsing.productActiveChartPoints(product.series.productActiveUsersPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(
                    AdminProductAnalyticsParsing.productActiveChartPoints(product.series.productActiveUsersPerDay)
                )
            )
            AdminUsageLineChartSection(
                title: "Signups",
                subtitle: "New profiles per UTC day.",
                points: product.series.signupsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(product.series.signupsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(product.series.signupsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Returning users",
                subtitle: "Engaged users who were also engaged on a prior day.",
                points: product.series.returningUsersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(product.series.returningUsersPerDay)
            )
            AdminUsageLineChartSection(
                title: "Trades created",
                subtitle: "All trades logged per UTC day.",
                points: product.series.tradesCreatedPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(product.series.tradesCreatedPerDay)
            )
            AdminUsageLineChartSection(
                title: "Active traders",
                subtitle: "Distinct traders excluding broker bulk initial import.",
                points: product.series.activeTradersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(product.series.activeTradersPerDay)
            )
            AdminUsageLineChartSection(
                title: "Profile views",
                subtitle: "Profile view events rolled up per UTC day.",
                points: product.series.profileViewsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(product.series.profileViewsPerDay)
            )
            if product.previewAvailable {
                AdminUsageLineChartSection(
                    title: "TraxsPro preview starts",
                    subtitle: "Interactive preview sessions started (iOS).",
                    points: product.series.previewStartsPerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(product.series.previewStartsPerDay)
                )
                AdminUsageLineChartSection(
                    title: "Preview upgrade taps",
                    subtitle: "Upgrade CTA tapped during preview.",
                    points: product.series.previewUpgradeTapsPerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(product.series.previewUpgradeTapsPerDay)
                )
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func metricLabel(_ value: Int?) -> String {
        guard let value else { return "—" }
        return NumberDisplay.integer(value)
    }

    private func ratioLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return NumberDisplay.decimal(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return NumberDisplay.decimal(value, minimumFractionDigits: 1, maximumFractionDigits: 1) + "%"
    }

    private func retentionLabel(rate: Double?, mature: Int, insufficient: Bool) -> String {
        if insufficient || mature <= 0 { return "Insufficient data" }
        return percentLabel(rate)
    }

    @ViewBuilder
    private func productFeaturesTable(_ product: AdminProductAnalyticsBundle) -> some View {
        if !product.topFeatures.isEmpty {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Feature usage (distinct users in period)")
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(product.topFeatures, id: \.feature) { row in
                HStack {
                    Text(row.feature.isEmpty ? "—" : row.feature)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                    Spacer()
                    Text("Uses \(NumberDisplay.integer(row.useCount))")
                        .experienceStyle(.caption, color: colors.secondaryText)
                    Text("W \(NumberDisplay.integer(row.webUniqueUsers))")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                    Text("iOS \(NumberDisplay.integer(row.iosUniqueUsers))")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        }
    }

    @ViewBuilder
    private var lifecycleAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Lifecycle analytics")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            Picker("Lifecycle range", selection: $viewModel.lifecycleQuery.preset) {
                ForEach(AdminLifecycleAnalyticsPreset.allCases, id: \.self) { preset in
                    Text(preset.menuLabel).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ExperienceSpacing.md)
            .onChange(of: viewModel.lifecycleQuery.preset) { _, _ in
                Task { await viewModel.onLifecycleQueryChanged() }
            }

            if let lifecycle = viewModel.lifecycleBundle {
                if !lifecycle.notes.isEmpty {
                    Text(lifecycle.notes.joined(separator: " "))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                }
                Text("Activation funnel")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
                ForEach(lifecycle.activationStages, id: \.id) { stage in
                    HStack {
                        Text(stage.label)
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Spacer()
                        Text(NumberDisplay.integer(stage.count))
                            .experienceStyle(.caption, color: colors.primaryText)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                Text("TraxsPro funnel")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
                ForEach(lifecycle.traxsProStages, id: \.id) { stage in
                    HStack {
                        Text(stage.label)
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Spacer()
                        Text(NumberDisplay.integer(stage.count))
                            .experienceStyle(.caption, color: colors.primaryText)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                summaryCard(
                    "Session D1",
                    retentionLabel(
                        rate: lifecycle.sessionD1Rate,
                        mature: lifecycle.sessionD1MatureCohortSize,
                        insufficient: lifecycle.sessionRetentionInsufficientData
                    )
                )
                .padding(.horizontal, ExperienceSpacing.md)
            } else if let error = viewModel.lifecycleErrorMessage {
                Text(error)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }

    @ViewBuilder
    private var historicalEngagementSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Historical engagement")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)
            Text(AdminHistoricalEngagementDefinition.engagedUsers)
                .experienceStyle(.caption, color: colors.tertiaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            Picker("Historical range", selection: $viewModel.historicalQuery.preset) {
                ForEach(AdminHistoricalEngagementPreset.allCases, id: \.self) { preset in
                    Text(preset.menuLabel).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ExperienceSpacing.md)
            .onChange(of: viewModel.historicalQuery.preset) { _, _ in
                Task { await viewModel.onHistoricalQueryChanged() }
            }

            if viewModel.historicalQuery.preset == .custom {
                HStack(spacing: ExperienceSpacing.sm) {
                    TextField("Start YYYY-MM-DD", text: Binding(
                        get: { viewModel.historicalQuery.customStartDate ?? "" },
                        set: { viewModel.historicalQuery.customStartDate = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    TextField("End YYYY-MM-DD", text: Binding(
                        get: { viewModel.historicalQuery.customEndDate ?? "" },
                        set: { viewModel.historicalQuery.customEndDate = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .onSubmit { Task { await viewModel.onHistoricalQueryChanged() } }

                if let validation = AdminHistoricalEngagementQueryStore.validate(viewModel.historicalQuery) {
                    Text(validation)
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                }
            }

            Picker("Activity", selection: $viewModel.historicalQuery.activityFilter) {
                ForEach(AdminHistoricalActivityFilter.allCases, id: \.self) { filter in
                    Text(filter.menuLabel).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ExperienceSpacing.md)
            .onChange(of: viewModel.historicalQuery.activityFilter) { _, _ in
                Task { await viewModel.onHistoricalQueryChanged() }
            }

            if let historical = viewModel.historicalBundle {
                if !historical.meta.notes.isEmpty {
                    Text(historical.meta.notes.joined(separator: " "))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                }
                historicalOverview(historical)
                historicalCharts(historical)
            } else if let error = viewModel.historicalErrorMessage {
                productAnalyticsUnavailable(error)
            }
        }
    }

    @ViewBuilder
    private func historicalOverview(_ historical: AdminHistoricalEngagementBundle) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: ExperienceSpacing.sm
        ) {
            summaryCard("Engaged DAU", NumberDisplay.integer(historical.overview.engagedDau))
            summaryCard("Engaged WAU", NumberDisplay.integer(historical.overview.engagedWau))
            summaryCard("Engaged MAU", NumberDisplay.integer(historical.overview.engagedMau))
            summaryCard("Active traders", NumberDisplay.integer(historical.overview.activeTradersDau))
            summaryCard("Active creators", NumberDisplay.integer(historical.overview.activeCreatorsDau))
            summaryCard("Messengers", NumberDisplay.integer(historical.overview.activeMessengersDau))
            summaryCard(
                "Content D1",
                retentionLabel(
                    rate: historical.retentionD1Rate,
                    mature: historical.retentionD1MatureCohortSize,
                    insufficient: historical.retentionInsufficientData
                )
            )
            summaryCard(
                "Content D7",
                retentionLabel(
                    rate: historical.retentionD7Rate,
                    mature: historical.retentionD7MatureCohortSize,
                    insufficient: historical.retentionInsufficientData
                )
            )
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    @ViewBuilder
    private func historicalCharts(_ historical: AdminHistoricalEngagementBundle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            AdminUsageLineChartSection(
                title: "Engaged users / day",
                subtitle: AdminHistoricalEngagementDefinition.engagedUsers,
                points: historical.series.engagedUsersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(historical.series.engagedUsersPerDay)
            )
            AdminUsageLineChartSection(
                title: "Returning engaged users",
                subtitle: "Users with content activity after a prior active day.",
                points: historical.series.returningEngagedUsersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(historical.series.returningEngagedUsersPerDay)
            )
            if viewModel.showHistoricalTradingCharts {
                AdminUsageLineChartSection(
                    title: "Organic trades logged",
                    subtitle: "Excludes bulk is_initial_import rows.",
                    points: historical.trading.organicTradesLoggedPerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(historical.trading.organicTradesLoggedPerDay)
                )
                AdminUsageLineChartSection(
                    title: "Trades by execution date",
                    subtitle: AdminHistoricalEngagementDefinition.executionDates,
                    points: historical.trading.tradesByExecutionDatePerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(historical.trading.tradesByExecutionDatePerDay)
                )
                AdminUsageLineChartSection(
                    title: "Active traders",
                    subtitle: "Distinct organic trade loggers per day.",
                    points: historical.trading.activeTradersPerDay,
                    periodAverage: AdminUsageAnalyticsMath.averagePerDay(historical.trading.activeTradersPerDay)
                )
            }
            AdminUsageLineChartSection(
                title: "Signups",
                subtitle: "New profiles per UTC day.",
                points: historical.series.signupsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(historical.series.signupsPerDay)
            )
            if viewModel.showHistoricalSocialCharts {
                AdminUsageLineChartSection(
                    title: "Messages sent",
                    subtitle: "Outbound messages created per UTC day.",
                    points: historical.social.messagesPerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(historical.social.messagesPerDay)
                )
                AdminUsageLineChartSection(
                    title: "New follows",
                    subtitle: "Follow relationships created per day.",
                    points: historical.social.followsPerDay,
                    periodTotal: AdminUsageAnalyticsMath.totalCount(historical.social.followsPerDay)
                )
                AdminUsageLineChartSection(
                    title: "Active creators",
                    subtitle: "Posts, profile posts, or reels per day.",
                    points: historical.social.activeCreatorsPerDay,
                    periodAverage: AdminUsageAnalyticsMath.averagePerDay(historical.social.activeCreatorsPerDay)
                )
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    @ViewBuilder
    private func charts(_ bundle: AdminUsageAnalyticsBundle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text("Legacy activity metrics")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(AdminProductAnalyticsDefinition.legacyActivityDau)
                .experienceStyle(.caption, color: colors.tertiaryText)
                .padding(.top, ExperienceSpacing.xxs)
            AdminUsageLineChartSection(
                title: "Daily Active Users",
                subtitle: AdminUsageAnalyticsDefinition.dailyActiveUsersPerDay,
                points: bundle.series.activeUsersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.activeUsersPerDay)
            )
            AdminUsageLineChartSection(
                title: "New Signups",
                subtitle: "New profiles created per UTC day.",
                points: bundle.series.usersPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.usersPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.usersPerDay)
            )
            AdminUsageLineChartSection(
                title: "Posts Per Day",
                subtitle: "Feed posts created per UTC day.",
                points: bundle.series.postsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.postsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.postsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Trades Added Per Day",
                subtitle: "Trades logged per UTC day.",
                points: bundle.series.tradesPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.tradesPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.tradesPerDay)
            )
            AdminUsageLineChartSection(
                title: "Reels / Clips Per Day",
                subtitle: "Reels published per UTC day.",
                points: bundle.series.reelsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.reelsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.reelsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Comments Per Day",
                subtitle: "Comments created per UTC day.",
                points: bundle.series.commentsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.commentsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.commentsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Likes Per Day",
                subtitle: "Likes created per UTC day.",
                points: bundle.series.likesPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.likesPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.likesPerDay)
            )
            AdminUsageLineChartSection(
                title: "Follows Per Day",
                subtitle: "New follow relationships per UTC day.",
                points: bundle.series.followsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.followsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.followsPerDay)
            )
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }
}
