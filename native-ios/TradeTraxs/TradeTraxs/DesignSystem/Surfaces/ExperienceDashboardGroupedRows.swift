import SwiftUI
import UIKit

extension View {
    /// Dark mode only. Inset-grouped form and settings rows use the Dashboard card
    /// lift (`fillSecondary` at 35% over the page) instead of the system warm grouped fill.
    /// Light mode is left untouched.
    func experienceDashboardGroupedRows() -> some View {
        modifier(ExperienceDashboardGroupedRowsModifier())
    }

    /// Dark mode only. One list/form row painted with the same opaque Dashboard card composite.
    /// Light mode keeps the system row.
    func experienceDashboardListRow() -> some View {
        modifier(ExperienceDashboardListRowModifier())
    }
}

private struct ExperienceDashboardListRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.listRowBackground(
                ExperienceDashboardGroupedSurface.rowColor(
                    page: colors.backgroundPrimary,
                    lift: colors.fillSecondary
                )
            )
        } else {
            content
        }
    }
}

private struct ExperienceDashboardGroupedRowsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .scrollContentBackground(.hidden)
                .background {
                    ExperienceDashboardGroupedRowInstaller(
                        rowColor: ExperienceDashboardGroupedSurface.rowUIColor(
                            page: colors.backgroundPrimary,
                            lift: colors.fillSecondary
                        ),
                        pageColor: UIColor(colors.backgroundPrimary)
                    )
                    .allowsHitTesting(false)
                }
                .background(colors.backgroundPrimary.ignoresSafeArea())
        } else {
            content
        }
    }
}

private enum ExperienceDashboardGroupedSurface {
    /// Opaque composite matching Dashboard cards: `fillSecondary.opacity(0.35)` over the page.
    static func rowColor(page: Color, lift: Color) -> Color {
        Color(uiColor: rowUIColor(page: page, lift: lift))
    }

    static func rowUIColor(page: Color, lift: Color) -> UIColor {
        let pageColor = UIColor(page)
        let liftColor = UIColor(lift)
        return UIColor { traits in
            blend(
                pageColor.resolvedColor(with: traits),
                over: liftColor.resolvedColor(with: traits),
                amount: 0.35
            )
        }
    }

    private static func blend(_ base: UIColor, over overlay: UIColor, amount: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        else { return base }
        return UIColor(
            red: br + (or - br) * amount,
            green: bg + (og - bg) * amount,
            blue: bb + (ob - bb) * amount,
            alpha: 1
        )
    }
}

private struct ExperienceDashboardGroupedRowInstaller: UIViewRepresentable {
    var rowColor: UIColor
    var pageColor: UIColor

    func makeUIView(context: Context) -> ExperienceDashboardGroupedRowInstallerView {
        let view = ExperienceDashboardGroupedRowInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.rowColor = rowColor
        view.pageColor = pageColor
        return view
    }

    func updateUIView(_ view: ExperienceDashboardGroupedRowInstallerView, context: Context) {
        view.rowColor = rowColor
        view.pageColor = pageColor
        view.scheduleApply()
    }
}

private final class ExperienceDashboardGroupedRowInstallerView: UIView {
    var rowColor: UIColor = .clear
    var pageColor: UIColor = .clear

    private var observedList: UICollectionView?
    private var offsetObservation: NSKeyValueObservation?
    private var applyScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            offsetObservation?.invalidate()
            offsetObservation = nil
            observedList = nil
        } else {
            scheduleApply()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleApply()
    }

    func scheduleApply() {
        guard window != nil, !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.apply()
        }
    }

    private func apply() {
        guard let list = nearestList() else { return }
        attachIfNeeded(to: list)
        list.backgroundColor = .clear
        for case let cell as UICollectionViewListCell in list.visibleCells where shouldPaint(cell) {
            paint(cell)
        }
    }

    private func attachIfNeeded(to list: UICollectionView) {
        guard list !== observedList else { return }
        offsetObservation?.invalidate()
        observedList = list
        offsetObservation = list.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.scheduleApply()
                }
            }
        }
    }

    private func nearestList() -> UICollectionView? {
        var ancestor: UIView? = superview
        var depth = 0
        while let current = ancestor, depth < 8 {
            if let list = firstCollectionView(in: current, excluding: self) {
                return list
            }
            ancestor = current.superview
            depth += 1
        }
        return nil
    }

    private func firstCollectionView(in root: UIView, excluding: UIView) -> UICollectionView? {
        var queue: [UIView] = root.subviews.filter { $0 !== excluding && !$0.isDescendant(of: excluding) }
        var index = 0
        while index < queue.count, index < 240 {
            let view = queue[index]
            index += 1
            if let list = view as? UICollectionView {
                return list
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func shouldPaint(_ cell: UICollectionViewListCell) -> Bool {
        guard let config = cell.backgroundConfiguration else { return false }
        if config.visualEffect != nil { return true }
        guard let color = config.backgroundColor else { return false }
        let traits = cell.traitCollection
        let resolved = color.resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0.04 else {
            return false
        }
        if colorsClose(resolved, pageColor.resolvedColor(with: traits)) { return false }
        if colorsClose(resolved, rowColor.resolvedColor(with: traits)) { return false }
        return true
    }

    private func paint(_ cell: UICollectionViewListCell) {
        var config = cell.backgroundConfiguration ?? UIBackgroundConfiguration.listCell()
        config.visualEffect = nil
        config.backgroundColor = rowColor
        cell.backgroundConfiguration = config
    }

    private func colorsClose(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        else { return false }
        return abs(lr - rr) < 0.03 && abs(lg - rg) < 0.03 && abs(lb - rb) < 0.03
    }

    deinit {
        offsetObservation?.invalidate()
    }
}
