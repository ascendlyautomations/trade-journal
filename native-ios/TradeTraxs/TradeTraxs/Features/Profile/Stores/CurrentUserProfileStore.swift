import Foundation
import Observation
import SwiftUI
import UIKit

/// App-session cache for the authenticated user's profile header + tab avatar.
///
/// Single load path shared by Profile screen and bottom navigation.
/// Cleared on logout. Features never talk to Supabase — only repositories / image pipeline.
@Observable
@MainActor
final class CurrentUserProfileStore {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var profile: Profile?
    private(set) var stats: ProfileStats?
    private(set) var avatarImage: Image?
    /// Source bitmap for header + tab bar (no extra network — same pipeline load).
    private(set) var avatarUIImage: UIImage?
    /// Pre-clipped circular tab icon (`alwaysOriginal`) for native `Tab` labels.
    private(set) var tabBarAvatarUIImage: UIImage?
    private(set) var errorMessage: String?

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache?

    private var loadTask: Task<Void, Never>?
    private var loadedProfileID: ProfileID?
    private var loadedAvatarKey: String?

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        imagePipeline: any ImagePipeline,
        detailCache: DetailPresentationCache? = nil
    ) {
        self.profiles = profiles
        self.session = session
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
    }

    var initials: String {
        guard let profile else { return "" }
        return ProfileDisplay.initials(displayName: profile.displayName, username: profile.username)
    }

    var hasLoadedContent: Bool {
        profile != nil
    }

    /// Loads once per authenticated session unless `force` is true.
    func loadIfNeeded(force: Bool = false) {
        if let loadTask, !force {
            return
        }
        if !force, phase == .loaded, profile != nil {
            return
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(force: force)
        }
    }

    func refresh() {
        loadIfNeeded(force: true)
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        phase = .idle
        profile = nil
        stats = nil
        avatarImage = nil
        avatarUIImage = nil
        tabBarAvatarUIImage = nil
        errorMessage = nil
        loadedProfileID = nil
        loadedAvatarKey = nil
    }

    private func performLoad(force: Bool) async {
        phase = profile == nil ? .loading : phase
        errorMessage = nil

        guard let userID = await session.currentUserID else {
            phase = .failed
            errorMessage = UserFacingError.map(AppError.domain(.permission(.notAuthenticated))).message
            loadTask = nil
            return
        }

        let profileID = ProfileID(userID.rawValue)

        do {
            async let profileTask = profiles.profile(id: profileID)
            async let statsTask = profiles.stats(for: profileID)
            let (loadedProfile, loadedStats) = try await (profileTask, statsTask)

            guard !Task.isCancelled else { return }

            profile = loadedProfile
            stats = loadedStats
            loadedProfileID = profileID
            phase = .loaded
            // Seed shared detail cache so Profile screen can skip a second profile/stats fan-out.
            detailCache?.seed(loadedProfile)
            detailCache?.seed(stats: loadedStats)

            await loadAvatarIfNeeded(for: loadedProfile, force: force)
        } catch is CancellationError {
            // Keep prior content.
        } catch {
            if profile == nil {
                phase = .failed
            }
            errorMessage = UserFacingError.map(error as? AppError ?? AppError.unknown(message: error.localizedDescription)).message
        }

        loadTask = nil
    }

    private func loadAvatarIfNeeded(for profile: Profile, force: Bool) async {
        guard let reference = profile.avatar else {
            clearAvatarImages()
            return
        }

        if !force, loadedAvatarKey == reference.id, avatarUIImage != nil {
            return
        }

        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 512
                )
            )
            guard !Task.isCancelled else { return }
            guard let uiImage = UIImage(data: data) else {
                clearAvatarImages()
                return
            }
            avatarUIImage = uiImage
            avatarImage = Image(uiImage: uiImage)
            tabBarAvatarUIImage = Self.makeTabBarAvatar(from: uiImage)
            loadedAvatarKey = reference.id
        } catch {
            // Keep initials / default tab symbol — never block the header on image failure.
            clearAvatarImages()
        }
    }

    private func clearAvatarImages() {
        avatarImage = nil
        avatarUIImage = nil
        tabBarAvatarUIImage = nil
        loadedAvatarKey = nil
    }

    /// Circular, tab-sized bitmap so SwiftUI `Tab` keeps native chrome / selection.
    static func makeTabBarAvatar(from image: UIImage, side: CGFloat = 28) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rounded = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()
            let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rounded.withRenderingMode(.alwaysOriginal)
    }
}

enum ProfileDisplay {
    static func initials(displayName: String, username: String) -> String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = source.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(handle.prefix(2)).uppercased()
    }

    static func compactCount(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            let scaled = Double(absolute) / 1_000_000
            return trimmedCompact(scaled) + "M"
        }
        if absolute >= 1_000 {
            let scaled = Double(absolute) / 1_000
            return trimmedCompact(scaled) + "K"
        }
        return "\(value)"
    }

    /// Social line for the identity block — followers / following only.
    static func socialSummary(followers: Int, following: Int) -> String {
        "\(compactCount(followers)) Followers • \(compactCount(following)) Following"
    }

    /// Web `formatProfileMetadataLine` — style · trader type · market · experience.
    /// Empty fields are omitted (no `—` / `N/A` placeholders).
    static func metadataLine(for profile: Profile, now: Date = Date()) -> String? {
        var parts: [String] = []

        if let style = profile.tradingStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !style.isEmpty
        {
            parts.append(style)
        }
        if let traderType = profile.traderType {
            parts.append(traderType.rawValue)
        }
        if let market = profile.primaryMarket?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !market.isEmpty
        {
            parts.append(market)
        }
        if let experience = tradingExperience(from: profile.startedTradingAt, now: now) {
            parts.append(experience)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Web `getExperience` — `"3y 2m"` from `started_trading`.
    static func tradingExperience(from start: Date?, now: Date = Date()) -> String? {
        guard let start else { return nil }
        let calendar = Calendar.current
        // Mirror web: `(now.year - start.year) * 12 + (now.month - start.month)`.
        let totalMonths =
            (calendar.component(.year, from: now) - calendar.component(.year, from: start)) * 12
            + (calendar.component(.month, from: now) - calendar.component(.month, from: start))
        guard totalMonths >= 0 else { return nil }
        return "\(totalMonths / 12)y \(totalMonths % 12)m"
    }

    /// Header statistics row built from cached ``ProfileStats``.
    ///
    /// Trades uses ``ProfileStats/publicTradeCount`` exclusively.
    /// Payouts uses ``ProfileStats/payoutTotal`` (web overview payout achievement sum).
    /// Win % / Profit Factor / Payouts show placeholders until those fields are cached.
    static func headerMetrics(from stats: ProfileStats?) -> [ProfileHeaderMetric] {
        [
            ProfileHeaderMetric(
                id: "posts",
                label: "Posts",
                value: compactCount(stats?.postCount ?? 0)
            ),
            ProfileHeaderMetric(
                id: "publicTrades",
                label: "Trades",
                value: compactCount(stats?.publicTradeCount ?? 0)
            ),
            ProfileHeaderMetric(
                id: "payouts",
                label: "Payouts",
                value: formatMoney(stats?.payoutTotal)
            ),
            ProfileHeaderMetric(
                id: "winRate",
                label: "Win %",
                value: formatWinRate(stats?.winRate)
            ),
            ProfileHeaderMetric(
                id: "profitFactor",
                label: "Profit Factor",
                value: formatProfitFactor(stats?.profitFactor)
            ),
        ]
    }

    static func formatWinRate(_ rate: Decimal?) -> String {
        guard let rate else { return ProfileHeaderMetric.placeholderValue }
        let percent = NSDecimalNumber(decimal: rate * 100).doubleValue
        // Web overview uses formatDecimal; keep a compact locale-stable percent.
        if percent.rounded() == percent {
            return "\(Int(percent))%"
        }
        let tenths = Int((percent * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)%"
    }

    static func formatProfitFactor(_ factor: Decimal?) -> String {
        guard let factor else { return ProfileHeaderMetric.placeholderValue }
        let value = NSDecimalNumber(decimal: factor).doubleValue
        return trimmedCompact(value)
    }

    static func formatMoney(_ amount: Decimal?) -> String {
        guard let amount else { return ProfileHeaderMetric.placeholderValue }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let absAmount = abs(amount)
        let body = formatter.string(from: NSDecimalNumber(decimal: absAmount)) ?? "\(absAmount)"
        return amount < 0 ? "-$\(body)" : "$\(body)"
    }

    private static func trimmedCompact(_ value: Double) -> String {
        // Locale-stable formatting (avoids "1,3K" vs "1.3K").
        if value.rounded() == value {
            return String(Int(value))
        }
        let tenths = Int((value * 10).rounded())
        let whole = tenths / 10
        let fraction = tenths % 10
        return fraction == 0 ? "\(whole)" : "\(whole).\(fraction)"
    }
}
