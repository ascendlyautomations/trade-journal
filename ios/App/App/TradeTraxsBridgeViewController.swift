import UIKit
import Capacitor
import WebKit

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

  /// Matches LaunchScreen + Capacitor `backgroundColor` (#0b1f3a).
  private static let shellBackground = UIColor(
    red: 11.0 / 255.0,
    green: 31.0 / 255.0,
    blue: 58.0 / 255.0,
    alpha: 1.0
  )

  override open func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Self.shellBackground
    webView?.backgroundColor = Self.shellBackground
    webView?.isOpaque = false
    webView?.scrollView.backgroundColor = Self.shellBackground
    installSplashOverlayIfNeeded()
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Prefer the window so the cover includes the status-bar band (LaunchScreen
    // was full-bleed; the WebView sits below the status bar when overlay=false).
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

    // Hide the login "Go home" control on native only (web app source unchanged).
    let hideBackCSS = """
    (function() {
      if (window.__ttHideLoginBackWired) return;
      window.__ttHideLoginBackWired = true;
      var css = 'button[aria-label="Go home"]{display:none!important;visibility:hidden!important;pointer-events:none!important;opacity:0!important;}';
      var style = document.createElement('style');
      style.id = 'tt-native-login-back-style';
      style.textContent = css;
      function mount() {
        var parent = document.head || document.documentElement;
        if (parent && !document.getElementById('tt-native-login-back-style')) {
          parent.appendChild(style);
        }
      }
      mount();
      document.addEventListener('DOMContentLoaded', mount);
    })();
    """
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

      function isMeaningfulFrame() {
        var p = path();
        if (isTransitPath(p)) return false;
        var root = document.documentElement;
        if (!root) return false;

        // Login: NativeIosLoginShell sets tt-ios-auth after the native chrome mounts.
        if (p.indexOf('/login') === 0) {
          return root.classList.contains('tt-ios-auth');
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
      WKUserScript(source: hideBackCSS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )
    controller.addUserScript(
      WKUserScript(source: launchReadyJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )
  }

  private func installSplashOverlayIfNeeded() {
    guard !splashDismissed else { return }

    let host: UIView
    if let window = view.window {
      host = window
    } else if let webView {
      host = webView
    } else {
      host = view
    }

    if let existing = splashOverlay {
      if existing.superview !== host {
        existing.removeFromSuperview()
        host.addSubview(existing)
        pinSplashOverlay(existing, to: host)
      }
      host.bringSubviewToFront(existing)
      return
    }

    let imageView = UIImageView(image: UIImage(named: "Splash"))
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.backgroundColor = Self.shellBackground
    imageView.isUserInteractionEnabled = true
    imageView.accessibilityIdentifier = "tt-native-splash-overlay"
    imageView.translatesAutoresizingMaskIntoConstraints = false

    host.addSubview(imageView)
    pinSplashOverlay(imageView, to: host)
    host.bringSubviewToFront(imageView)
    splashOverlay = imageView
  }

  private func pinSplashOverlay(_ overlay: UIView, to host: UIView) {
    NSLayoutConstraint.activate([
      overlay.topAnchor.constraint(equalTo: host.topAnchor),
      overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
    ])
  }

  private func dismissSplashOverlay() {
    guard !splashDismissed else { return }
    splashDismissed = true
    guard let overlay = splashOverlay else { return }
    splashOverlay = nil
    overlay.removeFromSuperview()
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
