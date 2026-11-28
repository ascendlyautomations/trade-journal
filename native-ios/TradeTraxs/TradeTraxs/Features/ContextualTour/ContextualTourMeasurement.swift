import CoreGraphics
import SwiftUI
import UIKit

/// Toolbar and navigation-bar controls may not publish `AnchorPreference` into the shell overlay.
@MainActor
@Observable
final class ContextualTourGlobalFrameStore {
  static let shared = ContextualTourGlobalFrameStore()

  private(set) var frames: [ContextualTourTargetID: CGRect] = [:]
  /// Bumps on each accepted global report so the shell overlay re-resolves tab/toolbar targets.
  private(set) var reportGeneration: UInt64 = 0

  func report(_ target: ContextualTourTargetID, frame: CGRect) {
    let coordinator = ContextualTourCoordinator.shared
    guard coordinator.measures(target) else { return }
    guard coordinator.acceptsGlobalMeasurement(for: target) else { return }
    guard ContextualTourGeometry.isUsable(frame) else { return }
    let previous = frames[target]
    frames[target] = frame
    if previous != frame {
      reportGeneration &+= 1
    }
  }

  func reset() {
    frames = [:]
    reportGeneration &+= 1
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
    .profileInsights,
    .profileSettings,
    .feedContentFilters,
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
    context.coordinator.syncPolling(to: uiView)
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

    func detach() {
      link?.invalidate()
      link = nil
      host = nil
    }

    func syncPolling(to view: UIView) {
      let coordinator = ContextualTourCoordinator.shared
      let shouldPoll =
        coordinator.phase == .preparing
        && coordinator.spotlightTarget?.isMainTabBarTarget == true
      if shouldPoll {
        attach(to: view)
      } else {
        detach()
      }
    }

    @objc private func tick() {
      let coordinator = ContextualTourCoordinator.shared
      guard coordinator.phase == .preparing,
            coordinator.spotlightTarget?.isMainTabBarTarget == true
      else { return }
      for tabTarget in ContextualTourTargetID.allCases where tabTarget.isMainTabBarTarget {
        guard coordinator.acceptsGlobalMeasurement(for: tabTarget),
              let tab = tabTarget.mainTabIdentifier
        else { continue }
        let frame = ContextualTourTabBarIntrospection.globalFrame(for: tab, trace: false)
        guard let frame else { continue }
        ContextualTourGlobalFrameStore.shared.report(tabTarget, frame: frame)
      }
    }
  }
}