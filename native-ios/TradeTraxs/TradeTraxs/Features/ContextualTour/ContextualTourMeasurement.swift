import CoreGraphics
import SwiftUI
import UIKit

/// Toolbar and navigation-bar controls may not publish `AnchorPreference` into the shell overlay.
@MainActor
@Observable
final class ContextualTourGlobalFrameStore {
  static let shared = ContextualTourGlobalFrameStore()

  private(set) var frames: [ContextualTourTargetID: CGRect] = [:]

  func report(_ target: ContextualTourTargetID, frame: CGRect) {
    guard ContextualTourCoordinator.shared.measures(target) else { return }
    guard ContextualTourGeometry.isUsable(frame) else { return }
    frames[target] = frame
  }

  func reset() {
    frames = [:]
  }
}

private struct ContextualTourGlobalFrameReporter: ViewModifier {
  let target: ContextualTourTargetID

  func body(content: Content) -> some View {
    if ContextualTourCoordinator.shared.measures(target) {
      content
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
          ContextualTourGlobalFrameStore.shared.report(target, frame: frame)
        }
    } else {
      content
    }
  }
}

extension View {
  /// Reports live global bounds for targets outside the anchor preference tree (e.g. toolbar).
  func contextualTourGlobalFrame(_ target: ContextualTourTargetID) -> some View {
    modifier(ContextualTourGlobalFrameReporter(target: target))
  }
}

enum ContextualTourTargetCatalog {
  static let globalMeasuredTargets: Set<ContextualTourTargetID> = [
    .mainTabHome,
    .mainTabFeed,
    .mainTabCreate,
    .mainTabMessages,
    .mainTabProfile,
    .dashboardCalendar,
    .feedExplore,
    .feedTradeRooms,
    .profileSettings,
  ]
}

/// Polls UIKit tab-bar control bounds while the walkthrough measures a tab target.
struct ContextualTourMainTabBarFrameReporter: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.attach(to: uiView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator {
    private weak var host: UIView?
    private var link: CADisplayLink?

    func attach(to view: UIView) {
      guard host !== view else {
        tick()
        return
      }
      link?.invalidate()
      host = view
      let link = CADisplayLink(target: self, selector: #selector(tick))
      link.add(to: .main, forMode: .common)
      self.link = link
      tick()
    }

    deinit {
      link?.invalidate()
    }

    @objc private func tick() {
      let coordinator = ContextualTourCoordinator.shared
      guard coordinator.phase == .measuring || coordinator.phase == .presenting else { return }
      for tabTarget in ContextualTourTargetID.allCases where tabTarget.isMainTabBarTarget {
        guard coordinator.measures(tabTarget), let tab = tabTarget.mainTabIdentifier else { continue }
        guard let frame = ContextualTourTabBarIntrospection.globalFrame(for: tab) else { continue }
        ContextualTourGlobalFrameStore.shared.report(tabTarget, frame: frame)
      }
    }
  }
}