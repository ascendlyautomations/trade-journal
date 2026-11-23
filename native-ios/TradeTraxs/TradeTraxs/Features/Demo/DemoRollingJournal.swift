import Foundation

/// Deterministic, Eastern-anchored demo journal for TraxsPro Preview and bundled Explore fallback.
nonisolated final class DemoRollingJournal: @unchecked Sendable {
    static let shared = DemoRollingJournal()

    private struct SeededRNG: Sendable {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0xDEAD_BEEF_CAFE : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ upper: Int) -> Int {
            guard upper > 0 else { return 0 }
            return Int(next() % UInt64(upper))
        }
    }

    struct Book: Sendable {
        var trades: [Trade]
        var checkIns: [TraderDailyCheckIn]
        var payouts: [AccountPayoutEntry]
    }

    private let lock = NSLock()
    private var cachedDayKey: String?
    private var cachedBook: Book?

    private init() {}

    func invalidateCache() {
        lock.lock()
        cachedDayKey = nil
        cachedBook = nil
        lock.unlock()
    }

    func book(now: Date = Date(), forceRebuild: Bool = false) -> Book {
        let dayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: now)
        lock.lock()
        if !forceRebuild, cachedDayKey == dayKey, let cachedBook {
            lock.unlock()
            return cachedBook
        }
        lock.unlock()
        let built = Self.buildBook(now: now)
        lock.lock()
        cachedDayKey = dayKey
        cachedBook = built
        lock.unlock()
        return built
    }

    func trades(now: Date = Date(), forceRebuild: Bool = false) -> [Trade] {
        book(now: now, forceRebuild: forceRebuild).trades
    }

    func checkIns(now: Date = Date(), forceRebuild: Bool = false) -> [TraderDailyCheckIn] {
        book(now: now, forceRebuild: forceRebuild).checkIns
    }

    func payouts(now: Date = Date(), forceRebuild: Bool = false) -> [AccountPayoutEntry] {
        book(now: now, forceRebuild: forceRebuild).payouts
    }

    // MARK: - Build

    private static func buildBook(now: Date) -> Book {
        let calendar = TradingReportPeriods.eastern
        let todayStart = calendar.startOfDay(for: now)
        guard let historyStart = calendar.date(byAdding: .month, value: -18, to: todayStart) else {
            return Book(trades: [], checkIns: [], payouts: [])
        }

        let owner = DemoCanonicalDataset.profileID
        let accounts = [
            DemoCanonicalDataset.evaluationAccountID,
            DemoCanonicalDataset.fundedAccountID,
            DemoCanonicalDataset.liveAccountID,
        ]
        let symbols = ["NQ", "MNQ", "ES"]
        let strategies = [
            "Opening drive",
            "Liquidity sweep",
            "VWAP rejection",
            "Failed breakdown",
            "NY lunch fade",
        ]
        let emotions = ["Calm", "Focused", "Confident", "FOMO", "Frustrated"]
        let screenshotURL =
            "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

        let currentWeekMonday = mondayOfWeek(containing: todayStart, calendar: calendar)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: todayStart)) ?? todayStart

        var trades: [Trade] = []
        trades.reserveCapacity(420)

        var day = historyStart
        while day <= todayStart {
            let weekday = calendar.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                continue
            }

            let dateKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: day)
            let dayOrdinal = calendar.dateComponents([.day], from: historyStart, to: day).day ?? 0
            var rng = SeededRNG(seed: hashSeed(dateKey))

            let inCurrentWeek = day >= currentWeekMonday
            let inCurrentMonth = day >= monthStart
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            let inLast30Days = day >= thirtyDaysAgo

            let tradesThisDay: Int = {
                if calendar.isDate(day, inSameDayAs: todayStart) { return 2 }
                if inCurrentWeek { return rng.int(2) == 0 ? 2 : 1 }
                if inCurrentMonth { return 1 + rng.int(2) }
                if inLast30Days { return 2 }
                return dayOrdinal % 5 == 0 ? 0 : 1
            }()

            for index in 0..<tradesThisDay {
                let sequence = trades.count
                let symbol = symbols[(sequence + index + dayOrdinal) % symbols.count]
                let side: TradeSide = (dayOrdinal + index) % 3 == 0 ? .short : .long
                let account = accounts[(dayOrdinal + index) % accounts.count]

                let strategy: String = {
                    if inLast30Days {
                        return strategies[(dayOrdinal + index * 2) % strategies.count]
                    }
                    return strategies[(dayOrdinal + index) % strategies.count]
                }()

                guard let entry = resolveEntry(
                    day: day,
                    index: index,
                    dayOrdinal: dayOrdinal,
                    now: now,
                    calendar: calendar
                ) else { continue }

                let pnl = realizedPnL(rng: &rng, dayOrdinal: dayOrdinal, index: index)
                let holdSeconds = holdDurationSeconds(
                    rng: &rng,
                    dayOrdinal: dayOrdinal,
                    index: index,
                    winning: pnl > 0,
                    losing: pnl < 0
                )
                var exit = entry.addingTimeInterval(TimeInterval(holdSeconds))
                if exit > now {
                    exit = now
                }
                guard exit > entry else { continue }
                let qty: Decimal = symbol == "MNQ" ? 4 : (symbol == "NQ" ? 2 : 1)
                let entryPrice: Decimal = symbol.hasPrefix("ES")
                    ? 5_150 + Decimal((dayOrdinal + index) % 120)
                    : 18_200 + Decimal((dayOrdinal + index) % 160)
                let points: Decimal = {
                    if pnl == 0 { return 0 }
                    let mag = Decimal(8 + rng.int(18))
                    return pnl > 0 ? mag : -mag
                }()
                let exitPrice = entryPrice + (side == .long ? points : -points)
                let rr = Decimal(string: String(format: "%.1f", 0.9 + Double(rng.int(12)) * 0.2)) ?? 1.2
                let maxRr = demoMaxRrReached(targetRr: rr, rng: &rng)

                let win = pnl > 0
                let followedPlan = win ? rng.int(10) < 8 : rng.int(10) < 4
                let emotion = emotions[rng.int(emotions.count)]
                let confidence = 2 + rng.int(4)
                let executionRating = win ? 3 + rng.int(3) : 1 + rng.int(3)
                let mistakeType: String? = win ? nil : (rng.int(4) == 0 ? "Moved stop" : nil)
                let isPublic = rng.int(5) != 1
                let hasNotes = rng.int(3) == 0
                let thumbnail = rng.int(4) == 0
                    ? MediaReference(id: screenshotURL, kind: .image, altText: "Chart")
                    : nil

                let tradeID = TradeID("demo-trade-\(dateKey)-\(index)")
                let mode: TradeMode = account == DemoCanonicalDataset.liveAccountID ? .live : .sim
                let accountMode: TradingAccountMode = {
                    switch account {
                    case DemoCanonicalDataset.evaluationAccountID: return .evaluation
                    case DemoCanonicalDataset.fundedAccountID: return .funded
                    default: return .live
                    }
                }()

                trades.append(
                    Trade(
                        id: tradeID,
                        ownerProfileID: owner,
                        accountID: account,
                        symbol: Symbol(ticker: symbol),
                        side: side,
                        mode: mode,
                        quantity: qty,
                        entryPrice: entryPrice,
                        exitPrice: exitPrice,
                        entryAt: entry,
                        exitAt: exit,
                        realizedPnL: Money(amount: pnl),
                        riskReward: rr,
                        maxRrReached: maxRr,
                        points: abs(points),
                        sessionLabel: TradingSessionLabel.session(from: entry) ?? sessionSlots[0].label,
                        visibility: isPublic ? .public : .private,
                        publicCaption: isPublic ? "Session recap" : nil,
                        thumbnail: thumbnail,
                        notePreview: hasNotes ? "Waited for confirmation; sized to plan." : nil,
                        strategy: strategy,
                        confidence: confidence,
                        emotion: emotion,
                        followedPlan: followedPlan,
                        mistakeType: mistakeType,
                        executionRating: executionRating,
                        durationSeconds: Int(exit.timeIntervalSince(entry)),
                        accountMode: accountMode,
                        createdAt: entry,
                        updatedAt: exit
                    )
                )
            }

            if day <= todayStart,
               !trades.contains(where: { TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0) == dateKey })
            {
                appendGuaranteedTrade(
                    on: day,
                    dayOrdinal: dayOrdinal,
                    dateKey: dateKey,
                    inLast30Days: inLast30Days,
                    now: now,
                    calendar: calendar,
                    owner: owner,
                    accounts: accounts,
                    symbols: symbols,
                    strategies: strategies,
                    emotions: emotions,
                    screenshotURL: screenshotURL,
                    trades: &trades
                )
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        trades.sort { $0.entryAt > $1.entryAt }

        let checkIns = buildCheckIns(from: trades, owner: owner)
        let payouts = buildPayouts(from: trades, now: now, calendar: calendar)

        return Book(trades: trades, checkIns: checkIns, payouts: payouts)
    }

  private static let sessionSlots: [(label: String, hour: Int, minute: Int)] = [
        ("NY AM", 9, 45),
        ("NY Lunch", 12, 15),
        ("NY PM", 14, 30),
        ("London", 4, 30),
        ("Asia", 20, 0),
    ]

    private static func easternSessionEntry(
        day: Date,
        slot: (label: String, hour: Int, minute: Int),
        index: Int,
        calendar: Calendar
    ) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let minuteBump = (index * 17) % 50
        if slot.hour >= 18 {
            comps.hour = slot.hour
            comps.minute = min(59, slot.minute + minuteBump)
        } else if slot.hour < 6 {
            comps.hour = slot.hour + min(index, 1)
            comps.minute = min(59, slot.minute + minuteBump)
        } else {
            comps.hour = min(15, slot.hour + (index % 2))
            comps.minute = min(59, slot.minute + minuteBump)
        }
        comps.timeZone = calendar.timeZone
        return calendar.date(from: comps)
    }

    private static func resolveEntry(
        day: Date,
        index: Int,
        dayOrdinal: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let startSlot = (dayOrdinal + index) % sessionSlots.count
        for offset in 0..<sessionSlots.count {
            let slot = sessionSlots[(startSlot + offset) % sessionSlots.count]
            if let entry = easternSessionEntry(day: day, slot: slot, index: index, calendar: calendar),
               entry <= now
            {
                return entry
            }
        }
        return nil
    }

    private static func appendGuaranteedTrade(
        on day: Date,
        dayOrdinal: Int,
        dateKey: String,
        inLast30Days: Bool,
        now: Date,
        calendar: Calendar,
        owner: ProfileID,
        accounts: [TradingAccountID],
        symbols: [String],
        strategies: [String],
        emotions: [String],
        screenshotURL: String,
        trades: inout [Trade]
    ) {
        let slotIndex = dayOrdinal % sessionSlots.count
        guard let entry = easternSessionEntry(
            day: day,
            slot: sessionSlots[slotIndex],
            index: 1,
            calendar: calendar
        ),
            entry <= now
        else { return }
        var rng = SeededRNG(seed: hashSeed("\(dateKey).guaranteed"))
        let index = 0
        let symbol = symbols[dayOrdinal % symbols.count]
        let side: TradeSide = dayOrdinal % 3 == 0 ? .short : .long
        let account = accounts[dayOrdinal % accounts.count]
        let strategy = inLast30Days
            ? strategies[dayOrdinal % strategies.count]
            : strategies[(dayOrdinal + 1) % strategies.count]
        let pnl = realizedPnL(rng: &rng, dayOrdinal: dayOrdinal, index: index)
        let holdSeconds = holdDurationSeconds(
            rng: &rng,
            dayOrdinal: dayOrdinal,
            index: index,
            winning: pnl > 0,
            losing: pnl < 0
        )
        var exit = entry.addingTimeInterval(TimeInterval(holdSeconds))
        if exit > now { exit = now }
        guard exit > entry else { return }
        let qty: Decimal = symbol == "MNQ" ? 4 : (symbol == "NQ" ? 2 : 1)
        let entryPrice: Decimal = symbol.hasPrefix("ES")
            ? 5_150 + Decimal(dayOrdinal % 120)
            : 18_200 + Decimal(dayOrdinal % 160)
        let points: Decimal = pnl == 0 ? 0 : (pnl > 0 ? Decimal(10 + rng.int(10)) : Decimal(-(8 + rng.int(6))))
        let exitPrice = entryPrice + (side == .long ? points : -points)
        let rr = Decimal(string: String(format: "%.1f", 1.1 + Double(rng.int(8)) * 0.2)) ?? 1.2
        let maxRr = demoMaxRrReached(targetRr: rr, rng: &rng)
        let win = pnl > 0
        let mode: TradeMode = account == DemoCanonicalDataset.liveAccountID ? .live : .sim
        trades.append(
            Trade(
                id: TradeID("demo-trade-\(dateKey)-guaranteed"),
                ownerProfileID: owner,
                accountID: account,
                symbol: Symbol(ticker: symbol),
                side: side,
                mode: mode,
                quantity: qty,
                entryPrice: entryPrice,
                exitPrice: exitPrice,
                entryAt: entry,
                exitAt: exit,
                realizedPnL: Money(amount: pnl),
                riskReward: rr,
                maxRrReached: maxRr,
                points: abs(points),
                sessionLabel: sessionSlots[0].label,
                visibility: .public,
                publicCaption: "Session recap",
                strategy: strategy,
                confidence: 3 + rng.int(2),
                emotion: emotions[rng.int(emotions.count)],
                followedPlan: win,
                executionRating: win ? 4 : 2,
                durationSeconds: Int(exit.timeIntervalSince(entry)),
                accountMode: account == DemoCanonicalDataset.liveAccountID ? .live : (account == DemoCanonicalDataset.fundedAccountID ? .funded : .evaluation),
                createdAt: entry,
                updatedAt: exit
            )
        )
    }

    private static func demoMaxRrReached(targetRr: Decimal, rng: inout SeededRNG) -> Decimal {
        let roll = rng.int(10)
        let factor: Double
        if roll < 3 {
            factor = 0.55 + Double(rng.int(6)) * 0.07
        } else if roll < 7 {
            factor = 0.9 + Double(rng.int(5)) * 0.04
        } else {
            factor = 1.08 + Double(rng.int(8)) * 0.14
        }
        let reached = (targetRr as NSDecimalNumber).doubleValue * factor
        return Decimal(string: String(format: "%.2f", max(0, reached))) ?? targetRr
    }

    private static func holdDurationSeconds(
        rng: inout SeededRNG,
        dayOrdinal: Int,
        index: Int,
        winning: Bool,
        losing: Bool
    ) -> Int {
        let shortBuckets = [180, 300, 420, 600, 900]
        let midBuckets = [900, 1_200, 1_800, 2_400, 3_600]
        let longBuckets = [3_600, 4_800, 5_400, 7_200, 10_800]
        let buckets: [Int]
        if winning {
            buckets = (dayOrdinal + index) % 3 == 0 ? midBuckets : shortBuckets
        } else if losing {
            buckets = (dayOrdinal + index) % 4 == 0 ? shortBuckets : longBuckets
        } else {
            buckets = midBuckets
        }
        return buckets[(dayOrdinal + index) % buckets.count] + rng.int(180)
    }

    private static func realizedPnL(rng: inout SeededRNG, dayOrdinal: Int, index: Int) -> Decimal {
        let roll = (dayOrdinal * 3 + index + rng.int(7)) % 11
        switch roll {
        case 0, 1: return Decimal(-(120 + rng.int(5) * 45))
        case 2: return 0
        default: return Decimal(95 + rng.int(8) * 75)
        }
    }

    private static func buildCheckIns(from trades: [Trade], owner: ProfileID) -> [TraderDailyCheckIn] {
        let grouped = Dictionary(grouping: trades) {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0)
        }
        return grouped.map { date, dayTrades in
            let pnl = dayTrades.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
            let goodDay = pnl > 0
            let anchor = dayTrades[0].entryAt
            return TraderDailyCheckIn(
                id: TraderDailyCheckInID("demo.checkin.\(date)"),
                ownerProfileID: owner,
                checkInDate: date,
                sleepHours: goodDay ? Decimal(string: "7.5") : Decimal(string: "5.5"),
                sleepQuality: goodDay ? 4 : 2,
                morningRating: goodDay ? 4 : 2,
                stressLevel: goodDay ? 2 : 4,
                energyLevel: goodDay ? 4 : 2,
                focusLevel: goodDay ? 5 : 2,
                notes: goodDay
                    ? "Slept through the night and stuck to the plan."
                    : "Short sleep. Noted the impulse to size up after the first loss.",
                createdAt: anchor,
                updatedAt: anchor
            )
        }
        .sorted { $0.checkInDate > $1.checkInDate }
    }

    private static func buildPayouts(
        from trades: [Trade],
        now: Date,
        calendar: Calendar
    ) -> [AccountPayoutEntry] {
        let funded = DemoCanonicalDataset.fundedAccountID
        let fundedWins = trades
            .filter { $0.accountID == funded && ($0.realizedPnL?.amount ?? 0) > 0 }
            .sorted { $0.entryAt < $1.entryAt }
        guard fundedWins.count >= 2 else {
            return defaultPayouts(now: now)
        }
        let first = fundedWins[fundedWins.count / 3]
        let recent = fundedWins[fundedWins.count - 2]
        return [
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-1"),
                accountID: funded,
                amount: Money(amount: 1_850),
                payoutDate: first.exitAt ?? first.entryAt,
                note: "First funded payout"
            ),
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-2"),
                accountID: funded,
                amount: Money(amount: 2_400),
                payoutDate: recent.exitAt ?? recent.entryAt,
                note: "Consistency week"
            ),
        ]
    }

    private static func defaultPayouts(now: Date) -> [AccountPayoutEntry] {
        let funded = DemoCanonicalDataset.fundedAccountID
        return [
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-1"),
                accountID: funded,
                amount: Money(amount: 1_850),
                payoutDate: now.addingTimeInterval(-86_400 * 45),
                note: "First funded payout"
            ),
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-2"),
                accountID: funded,
                amount: Money(amount: 2_400),
                payoutDate: now.addingTimeInterval(-86_400 * 18),
                note: "Consistency week"
            ),
        ]
    }

    private static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let diff = weekday == 1 ? -6 : 1 - weekday
        return calendar.date(byAdding: .day, value: diff, to: start) ?? start
    }

    private static func hashSeed(_ dateKey: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_393_164_769_137
        for byte in dateKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}