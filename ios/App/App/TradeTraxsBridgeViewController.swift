import UIKit
import Capacitor
import WebKit

/**
 * Persists the WebView URL across process death so relaunch does not bounce
 * through `/` → `/native` → dashboard and lose the previous screen.
 *
 * Brief Control Center / Notification Center must not force a navigation.
 * We only save state on resign-active; we never reload on become-active.
 */
class TradeTraxsBridgeViewController: CAPBridgeViewController {
  private static let lastUrlKey = "tt_last_webview_url"
  private var observingUrl = false

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
  }

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
