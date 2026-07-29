import UIKit
import Capacitor
import WebKit

/**
 * Full-bleed Splash cover that mirrors LaunchScreen.
 * Installed on the UIWindow in AppDelegate before the first frame so the
 * system launch image never hands off to the navy WebView shell.
 */
enum TradeTraxsLaunchSplash {
  static let accessibilityIdentifier = "tt-native-splash-overlay"

  /// Matches LaunchScreen + Capacitor `backgroundColor` (#0b1f3a).
  static let shellBackground = UIColor(
    red: 11.0 / 255.0,
    green: 31.0 / 255.0,
    blue: 58.0 / 255.0,
    alpha: 1.0
  )

  @discardableResult
  static func install(on host: UIView) -> UIView {
    if let existing = find(in: host) {
      if existing.superview !== host {
        existing.removeFromSuperview()
        host.addSubview(existing)
        pin(existing, to: host)
      }
      host.bringSubviewToFront(existing)
      return existing
    }

    let imageView = UIImageView(image: UIImage(named: "Splash"))
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.backgroundColor = shellBackground
    imageView.isUserInteractionEnabled = true
    imageView.accessibilityIdentifier = accessibilityIdentifier
    imageView.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(imageView)
    pin(imageView, to: host)
    host.bringSubviewToFront(imageView)
    return imageView
  }

  static func find(in root: UIView) -> UIView? {
    if root.accessibilityIdentifier == accessibilityIdentifier {
      return root
    }
    for subview in root.subviews {
      if let found = find(in: subview) {
        return found
      }
    }
    return nil
  }

  private static func pin(_ overlay: UIView, to host: UIView) {
    NSLayoutConstraint.activate([
      overlay.topAnchor.constraint(equalTo: host.topAnchor),
      overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
    ])
  }
}

/**
 * Avoids a retain cycle: WKUserContentController strongly retains its handlers.
 */
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?

  init(target: any WKScriptMessageHandler) {
    self.target = target
    super.init()
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

/**
 * Persists the WebView URL across process death so relaunch does not bounce
 * through `/` → `/native` → dashboard and lose the previous screen.
 *
 * Brief Control Center / Notification Center must not force a navigation.
 * We only save state on resign-active; we never reload on become-active.
 *
 * Cold-start handoff: a full-bleed Splash overlay mirrors LaunchScreen and
 * stays up until the first meaningful in-app frame (login or dashboard) is
 * painted — so the navy WebView shell never flashes between splash and UI.
 */
class TradeTraxsBridgeViewController: CAPBridgeViewController, WKScriptMessageHandler {
  private static let lastUrlKey = "tt_last_webview_url"
  private static let launchReadyHandlerName = "ttLaunchReady"
  private var observingUrl = false
  private var launchScriptsInstalled = false
  private var splashDismissed = false
  private var splashOverlay: UIView?
  private var launchMessageHandler: WeakScriptMessageHandler?

  override open func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = TradeTraxsLaunchSplash.shellBackground
    webView?.backgroundColor = TradeTraxsLaunchSplash.shellBackground
    // Opaque navy under page content — avoids any transparent reveal of UIWindow
    // / system backgrounds in the status-bar band once splash dismisses.
    webView?.isOpaque = true
    webView?.scrollView.backgroundColor = TradeTraxsLaunchSplash.shellBackground
    webView?.scrollView.contentInsetAdjustmentBehavior = .never
    installSplashOverlayIfNeeded()
  }

  override open var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Keep the cover on the window (full-bleed, including status-bar band).
    installSplashOverlayIfNeeded()
  }

  /**
   * When the native process was killed, Capacitor would otherwise load the
   * configured origin (then middleware → /native). Prefer the last in-app URL
   * so the user returns to the same screen.
   *
   * `allowNavigation` still covers sibling paths on the same host, so pointing
   * the initial serverURL at a deep link does not trap navigation.
   */
  override open func instanceDescriptor() -> InstanceDescriptor {
    let descriptor = super.instanceDescriptor()
    if let restored = Self.restorableHref(configuredOrigin: descriptor.serverURL) {
      descriptor.serverURL = restored
      CAPLog.print("⚡️  TradeTraxs restoring WebView at \(restored)")
    }
    return descriptor
  }

  override open func capacitorDidLoad() {
    super.capacitorDidLoad()
    // Scripts must be registered before the first loadWebView() in viewDidLoad.
    installLaunchUserScriptsIfNeeded()
    installSplashOverlayIfNeeded()
    startObservingUrl()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(persistWebViewUrl),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(persistWebViewUrl),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  deinit {
    stopObservingUrl()
    NotificationCenter.default.removeObserver(self)
    webView?.configuration.userContentController
      .removeScriptMessageHandler(forName: Self.launchReadyHandlerName)
  }

  // MARK: - Launch splash → first paint

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == Self.launchReadyHandlerName else { return }
    DispatchQueue.main.async { [weak self] in
      self?.dismissSplashOverlay()
    }
  }

  private func installLaunchUserScriptsIfNeeded() {
    guard !launchScriptsInstalled, let webView else { return }
    launchScriptsInstalled = true

    let controller = webView.configuration.userContentController
    let proxy = WeakScriptMessageHandler(target: self)
    launchMessageHandler = proxy
    controller.add(proxy, name: Self.launchReadyHandlerName)

    // Keep the native Splash cover until login/dashboard (or restored route)
    // has a meaningful painted frame — no setTimeout.
    let launchReadyJS = """
    (function() {
      if (window.__ttLaunchReadyWired) return;
      window.__ttLaunchReadyWired = true;

      function path() {
        try { return location.pathname || ''; } catch (e) { return ''; }
      }

      function isTransitPath(p) {
        return p === '/' || p === '/native' || p.indexOf('/native/') === 0;
      }

      function hasLoginUi() {
        return !!(
          document.querySelector('form') ||
          document.querySelector('input[type="email"], input[type="password"], input[name="email"]') ||
          document.querySelector('img[src*="tradetrax-bg"]')
        );
      }

      function isMeaningfulFrame() {
        var p = path();
        if (isTransitPath(p)) return false;
        var root = document.documentElement;
        if (!root) return false;

        // Login: SSR may already set tt-native-ios; tt-ios-auth follows on mount.
        if (p.indexOf('/login') === 0) {
          return (root.classList.contains('tt-ios-auth') || root.classList.contains('tt-native-ios')) && hasLoginUi();
        }

        // Authenticated app / restored deep links: NativeAppShell sets tt-native-ios.
        if (!root.classList.contains('tt-native-ios')) return false;
        if (p.indexOf('/dashboard') === 0) {
          return !!(document.querySelector('nav, main, [role="navigation"], a[href="/dashboard"]')
            || (document.body && document.body.childElementCount > 0));
        }
        return !!(document.body && (document.body.innerText || '').trim().length > 0);
      }

      function notify() {
        if (window.__ttLaunchReadySent) return;
        if (!isMeaningfulFrame()) return;
        // Double rAF: wait until the browser has committed a paint of this frame.
        requestAnimationFrame(function() {
          requestAnimationFrame(function() {
            if (window.__ttLaunchReadySent) return;
            if (!isMeaningfulFrame()) return;
            window.__ttLaunchReadySent = true;
            try {
              window.webkit.messageHandlers.\(Self.launchReadyHandlerName).postMessage({
                path: path()
              });
            } catch (e) {}
          });
        });
      }

      var obs = new MutationObserver(notify);
      obs.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class']
      });
      document.addEventListener('DOMContentLoaded', notify);
      window.addEventListener('load', notify);
      window.addEventListener('pageshow', notify);
      notify();
    })();
    """

    controller.addUserScript(
      WKUserScript(source: launchReadyJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )
  }

  private func installSplashOverlayIfNeeded() {
    guard !splashDismissed else { return }

    let host: UIView
    if let window = view.window {
      host = window
    } else if let window = (UIApplication.shared.delegate as? AppDelegate)?.window {
      host = window
    } else if let webView {
      host = webView
    } else {
      host = view
    }

    splashOverlay = TradeTraxsLaunchSplash.install(on: host)
  }

  private func dismissSplashOverlay() {
    guard !splashDismissed else { return }
    splashDismissed = true
    splashOverlay?.removeFromSuperview()
    splashOverlay = nil
    // Sweep leftovers if the cover was parented to window and/or webView.
    if let window = view.window {
      TradeTraxsLaunchSplash.find(in: window)?.removeFromSuperview()
    }
    if let window = (UIApplication.shared.delegate as? AppDelegate)?.window {
      TradeTraxsLaunchSplash.find(in: window)?.removeFromSuperview()
    }
    if let webView {
      TradeTraxsLaunchSplash.find(in: webView)?.removeFromSuperview()
    }
  }

  // MARK: - URL persistence

  override open func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    if keyPath == #keyPath(WKWebView.url) {
      persistWebViewUrl()
    }
  }

  @objc func persistWebViewUrl() {
    guard let href = webView?.url?.absoluteString, !href.isEmpty else { return }
    guard Self.isPersistableHref(href) else { return }
    UserDefaults.standard.set(href, forKey: Self.lastUrlKey)
  }

  private func startObservingUrl() {
    guard !observingUrl, let webView else { return }
    webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: [.new], context: nil)
    observingUrl = true
  }

  private func stopObservingUrl() {
    guard observingUrl, let webView else { return }
    webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
    observingUrl = false
  }

  private static func restorableHref(configuredOrigin: String?) -> String? {
    guard let saved = UserDefaults.standard.string(forKey: lastUrlKey),
          isPersistableHref(saved),
          let savedUrl = URL(string: saved)
    else {
      return nil
    }

    if let configured = configuredOrigin, let origin = URL(string: configured) {
      if savedUrl.host != origin.host { return nil }
      let savedPort = savedUrl.port ?? defaultPort(for: savedUrl)
      let originPort = origin.port ?? defaultPort(for: origin)
      if let savedPort, let originPort, savedPort != originPort { return nil }
    }

    return saved
  }

  private static func defaultPort(for url: URL) -> Int? {
    switch url.scheme?.lowercased() {
    case "https": return 443
    case "http": return 80
    default: return nil
    }
  }

  private static func isPersistableHref(_ href: String) -> Bool {
    guard let url = URL(string: href), let scheme = url.scheme?.lowercased() else {
      return false
    }
    guard scheme == "http" || scheme == "https" else { return false }
    let path = url.path.isEmpty ? "/" : url.path
    // Cold-start entry should not be restored — use middleware → /native once.
    if path == "/" { return false }
    if path == "/native" || path.hasPrefix("/native/") { return false }
    return true
  }
}
