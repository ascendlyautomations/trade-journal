import UIKit
import Capacitor
import WebKit

/**
 * TEMPORARY [tt-splash-debug] — mirrors NSLog to Documents/tt-splash.log so
 * physical-device sequences can be pulled via appDataContainer when console
 * streaming is unavailable. No startup/dismiss behavior changes.
 */
enum TradeTraxsSplashDebugLog {
  private static let fileName = "tt-splash.log"
  private static let queue = DispatchQueue(label: "tt.splash.debug.log")
  private static let formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static var logURL: URL? {
    // Prefer Caches — more reliably present early; Documents can be empty until used.
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent(fileName)
  }

  static func line(_ format: String, _ args: CVarArg...) {
    let message = String(format: format, arguments: args)
    NSLog("%@", message)
    // Flush synchronously so a stuck splash still has a durable trail on disk.
    queue.sync {
      guard let url = logURL else { return }
      let stamp = formatter.string(from: Date())
      let row = "\(stamp) \(message)\n"
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      guard let handle = try? FileHandle(forWritingTo: url) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      if let data = row.data(using: .utf8) {
        try? handle.write(contentsOf: data)
      }
      try? handle.synchronize()
    }
  }

  static func clear() {
    queue.sync {
      guard let url = logURL else { return }
      try? FileManager.default.removeItem(at: url)
    }
  }
}

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
    // TEMPORARY [tt-splash-debug]
    let hostDesc = String(describing: type(of: host))
    let hostPtr = String(describing: ObjectIdentifier(host))
    if let existing = find(in: host) {
      let moved = existing.superview !== host
      if moved {
        existing.removeFromSuperview()
        host.addSubview(existing)
        pin(existing, to: host)
      }
      host.bringSubviewToFront(existing)
      TradeTraxsSplashDebugLog.line(
        "[tt-splash] TradeTraxsLaunchSplash.install() REUSE host=%@ hostId=%@ moved=%@ overlayId=%@ superview=%@ windowCount=%ld",
        hostDesc,
        hostPtr,
        moved ? "true" : "false",
        String(describing: ObjectIdentifier(existing)),
        existing.superview.map { String(describing: type(of: $0)) } ?? "nil",
        UIApplication.shared.windows.count
      )
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
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] TradeTraxsLaunchSplash.install() CREATE host=%@ hostId=%@ overlayId=%@ isWindow=%@ windowCount=%ld",
      hostDesc,
      hostPtr,
      String(describing: ObjectIdentifier(imageView)),
      (host is UIWindow) ? "true" : "false",
      UIApplication.shared.windows.count
    )
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
  private var observingLoading = false
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
    // TEMPORARY [tt-splash-debug]
    TradeTraxsSplashDebugLog.line("[tt-splash] Bridge.viewDidLoad → installSplashOverlayIfNeeded")
    installSplashOverlayIfNeeded(caller: "viewDidLoad")
  }

  override open var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Keep the cover on the window (full-bleed, including status-bar band).
    // TEMPORARY [tt-splash-debug]
    TradeTraxsSplashDebugLog.line("[tt-splash] Bridge.viewDidAppear → installSplashOverlayIfNeeded")
    installSplashOverlayIfNeeded(caller: "viewDidAppear")
    // TEMPORARY [tt-launch-debug]
    if let webView {
      NSLog(
        "[ttLaunchReady] viewDidAppear bounds=%@ splashDismissed=%@ url=%@",
        NSCoder.string(for: webView.bounds),
        splashDismissed ? "true" : "false",
        webView.url?.absoluteString ?? "nil"
      )
      webView.evaluateJavaScript(
        """
        (function(){
          var h = !!(window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.ttLaunchReady);
          return {
            wired: !!window.__ttLaunchReadyWired,
            sent: !!window.__ttLaunchReadySent,
            handler: h,
            path: location.pathname || '',
            visibility: document.visibilityState,
            classes: document.documentElement ? String(document.documentElement.className||'').slice(0,120) : ''
          };
        })()
        """
      ) { result, error in
        if let error {
          NSLog("[ttLaunchReady] probe error %@", error.localizedDescription)
        } else {
          NSLog("[ttLaunchReady] probe %@", String(describing: result))
        }
      }
    }
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
    // TEMPORARY [tt-splash-debug]
    TradeTraxsSplashDebugLog.line("[tt-splash] Bridge.capacitorDidLoad → installSplashOverlayIfNeeded")
    installSplashOverlayIfNeeded(caller: "capacitorDidLoad")
    startObservingUrl()
    startObservingLoading()
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
    stopObservingLoading()
    NotificationCenter.default.removeObserver(self)
    webView?.configuration.userContentController
      .removeScriptMessageHandler(forName: Self.launchReadyHandlerName)
  }

  // MARK: - Launch splash → first paint

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    // TEMPORARY [tt-launch-debug] / [tt-splash-debug]
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] ttLaunchReady RECEIVED name=%@ body=%@ splashDismissed=%@ thread=%@",
      message.name,
      String(describing: message.body),
      splashDismissed ? "true" : "false",
      Thread.isMainThread ? "main" : "bg"
    )
    NSLog(
      "[ttLaunchReady] native didReceive name=%@ body=%@",
      message.name,
      String(describing: message.body)
    )
    guard message.name == Self.launchReadyHandlerName else {
      TradeTraxsSplashDebugLog.line("[tt-splash] didReceive IGNORE unexpected name=%@", message.name)
      return
    }
    TradeTraxsSplashDebugLog.line("[tt-splash] after didReceive → DispatchQueue.main.async { dismissSplashOverlay() }")
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        TradeTraxsSplashDebugLog.line("[tt-splash] after didReceive async: self deallocated — dismiss skipped")
        return
      }
      TradeTraxsSplashDebugLog.line("[tt-splash] after didReceive async RUNNING → dismissSplashOverlay()")
      self.dismissSplashOverlay()
      TradeTraxsSplashDebugLog.line("[tt-splash] after didReceive async: dismissSplashOverlay() returned")
      self.logOverlayAudit(reason: "post-dismiss-immediate")
    }
  }

  private func installLaunchUserScriptsIfNeeded() {
    guard !launchScriptsInstalled, let webView else {
      // TEMPORARY [tt-launch-debug]
      NSLog(
        "[ttLaunchReady] install SKIPPED installed=%@ webViewNil=%@",
        launchScriptsInstalled ? "true" : "false",
        webView == nil ? "true" : "false"
      )
      return
    }
    launchScriptsInstalled = true

    let controllerFromWebView = webView.configuration.userContentController
    // Capacitor assigns delegationHandler.contentController onto the config
    // BEFORE WKWebView init; compare identity to detect a disconnected UCC.
    let controllerFromBridge = (bridge as? CapacitorBridge)?
      .webViewDelegationHandler.contentController
    let sameUCC: Bool = {
      guard let controllerFromBridge else { return false }
      return controllerFromWebView === controllerFromBridge
    }()

    // TEMPORARY [tt-launch-debug]
    NSLog(
      "[ttLaunchReady] install BEGIN handler=%@ webViewBounds=%@ scriptCountBefore=%lu sameUCCAsCapBridge=%@ wvUCC=%@ bridgeUCC=%@",
      Self.launchReadyHandlerName,
      NSCoder.string(for: webView.bounds),
      UInt(controllerFromWebView.userScripts.count),
      sameUCC ? "true" : "false",
      String(describing: ObjectIdentifier(controllerFromWebView)),
      controllerFromBridge.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    )

    // Keep original registration target during diagnosis (do not silently switch UCC).
    let controller = controllerFromWebView
    let proxy = WeakScriptMessageHandler(target: self)
    launchMessageHandler = proxy
    controller.add(proxy, name: Self.launchReadyHandlerName)

    // Keep the native Splash cover until login/dashboard (or restored route)
    // has a meaningful painted frame — no setTimeout.
    // TEMPORARY [tt-launch-debug]: verbose pipeline logs; dismiss behavior unchanged.
    let launchReadyJS = """
    (function() {
      if (window.__ttLaunchReadyWired) {
        console.log('[ttLaunchReady] script already wired — skip');
        return;
      }
      window.__ttLaunchReadyWired = true;
      console.log('[ttLaunchReady] SCRIPT INJECTED atDocumentStart path=' + (location.pathname || ''));

      function path() {
        try { return location.pathname || ''; } catch (e) { return ''; }
      }

      function isTransitPath(p) {
        return p === '/' || p === '/native' || p.indexOf('/native/') === 0;
      }

      function frameDebug() {
        var p = path();
        var root = document.documentElement;
        var classes = root ? String(root.className || '') : '';
        var hasNative = !!(root && root.classList.contains('tt-native-ios'));
        var hasAuth = !!(root && root.classList.contains('tt-ios-auth'));
        var bodyLen = (document.body && (document.body.innerText || '').trim().length) || 0;
        var transit = isTransitPath(p);
        var meaningful = false;
        var fail = '';
        if (transit) {
          fail = 'transitPath';
        } else if (!root) {
          fail = 'noDocumentElement';
        } else if (p.indexOf('/login') === 0) {
          // Class-based readiness (442bed3) + SSR tt-native-ios (1f03e17).
          // Do not wait for form/img body nodes — that gated ttLaunchReady too late.
          meaningful = hasAuth || hasNative;
          if (!meaningful) fail = 'loginMissingNativeClass';
        } else if (!hasNative) {
          fail = 'missingTtNativeIos';
        } else if (p.indexOf('/dashboard') === 0) {
          meaningful = !!(document.querySelector('nav, main, [role="navigation"], a[href="/dashboard"]')
            || (document.body && document.body.childElementCount > 0));
          if (!meaningful) fail = 'dashboardEmpty';
        } else {
          meaningful = bodyLen > 0;
          if (!meaningful) fail = 'bodyTextEmpty';
        }
        return {
          path: p,
          transit: transit,
          meaningful: meaningful,
          fail: fail,
          hasNative: hasNative,
          hasAuth: hasAuth,
          bodyLen: bodyLen,
          classes: classes.slice(0, 120),
          visibility: document.visibilityState,
          hidden: !!document.hidden
        };
      }

      function isMeaningfulFrame() {
        return frameDebug().meaningful;
      }

      function handlerExists() {
        try {
          return !!(
            window.webkit &&
            window.webkit.messageHandlers &&
            window.webkit.messageHandlers.\(Self.launchReadyHandlerName) &&
            typeof window.webkit.messageHandlers.\(Self.launchReadyHandlerName).postMessage === 'function'
          );
        } catch (e) {
          return false;
        }
      }

      function notify(reason) {
        var dbg = frameDebug();
        console.log('[ttLaunchReady] notify reason=' + reason +
          ' path=' + dbg.path +
          ' meaningful=' + dbg.meaningful +
          ' fail=' + dbg.fail +
          ' sent=' + !!window.__ttLaunchReadySent +
          ' handler=' + handlerExists() +
          ' visibility=' + dbg.visibility +
          ' bodyLen=' + dbg.bodyLen +
          ' hasNative=' + dbg.hasNative +
          ' hasAuth=' + dbg.hasAuth);
        if (window.__ttLaunchReadySent) return;
        if (!dbg.meaningful) return;
        console.log('[ttLaunchReady] scheduling double rAF for postMessage');
        // Double rAF: wait until the browser has committed a paint of this frame.
        requestAnimationFrame(function() {
          console.log('[ttLaunchReady] rAF#1 fired visibility=' + document.visibilityState);
          requestAnimationFrame(function() {
            console.log('[ttLaunchReady] rAF#2 fired visibility=' + document.visibilityState);
            if (window.__ttLaunchReadySent) return;
            var dbg2 = frameDebug();
            console.log('[ttLaunchReady] pre-postMessage meaningful=' + dbg2.meaningful +
              ' fail=' + dbg2.fail + ' handler=' + handlerExists());
            if (!dbg2.meaningful) return;
            window.__ttLaunchReadySent = true;
            if (!handlerExists()) {
              console.error('[ttLaunchReady] BREAK: messageHandlers.\(Self.launchReadyHandlerName) missing');
              return;
            }
            try {
              console.log('[ttLaunchReady] postMessage NOW path=' + dbg2.path);
              window.webkit.messageHandlers.\(Self.launchReadyHandlerName).postMessage({
                path: dbg2.path,
                debug: true
              });
              console.log('[ttLaunchReady] postMessage returned');
            } catch (e) {
              console.error('[ttLaunchReady] BREAK: postMessage threw', e && (e.message || e));
            }
          });
        });
      }

      var obs = new MutationObserver(function() { notify('mutation'); });
      obs.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class']
      });
      document.addEventListener('DOMContentLoaded', function() { notify('DOMContentLoaded'); });
      window.addEventListener('load', function() { notify('load'); });
      window.addEventListener('pageshow', function() { notify('pageshow'); });
      console.log('[ttLaunchReady] handlerExists at wire=' + handlerExists());
      notify('immediate');
    })();
    """

    controller.addUserScript(
      WKUserScript(source: launchReadyJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    // TEMPORARY [tt-launch-debug]
    NSLog(
      "[ttLaunchReady] install END scriptCountAfter=%lu handlerRegistered on UCC",
      UInt(controller.userScripts.count)
    )
  }

  private func installSplashOverlayIfNeeded(caller: String = "unknown") {
    // TEMPORARY [tt-splash-debug]
    if splashDismissed {
      TradeTraxsSplashDebugLog.line(
        "[tt-splash] installSplashOverlayIfNeeded SKIP caller=%@ reason=splashDismissed",
        caller
      )
      return
    }

    let host: UIView
    let hostSource: String
    if let window = view.window {
      host = window
      hostSource = "view.window"
    } else if let window = (UIApplication.shared.delegate as? AppDelegate)?.window {
      host = window
      hostSource = "AppDelegate.window"
    } else if let webView {
      host = webView
      hostSource = "webView"
    } else {
      host = view
      hostSource = "view"
    }

    let preexisting = TradeTraxsLaunchSplash.find(in: host) != nil
      || (view.window.map { TradeTraxsLaunchSplash.find(in: $0) != nil } ?? false)
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] installSplashOverlayIfNeeded CALL caller=%@ hostSource=%@ host=%@ preexisting=%@ windows=%ld",
      caller,
      hostSource,
      String(describing: type(of: host)),
      preexisting ? "true" : "false",
      UIApplication.shared.windows.count
    )
    splashOverlay = TradeTraxsLaunchSplash.install(on: host)
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] installSplashOverlayIfNeeded DONE caller=%@ overlayId=%@",
      caller,
      splashOverlay.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    )
  }

  private func dismissSplashOverlay() {
    // TEMPORARY [tt-splash-debug]
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] dismissSplashOverlay CALLED splashDismissed=%@ overlayNil=%@ thread=%@",
      splashDismissed ? "true" : "false",
      splashOverlay == nil ? "true" : "false",
      Thread.isMainThread ? "main" : "bg"
    )
    guard !splashDismissed else {
      TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay SKIP already dismissed")
      return
    }
    splashDismissed = true
    let beforeId = splashOverlay.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    splashOverlay?.removeFromSuperview()
    splashOverlay = nil
    TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay removed splashOverlay ref id=%@", beforeId)

    // Sweep leftovers if the cover was parented to window and/or webView.
    if let window = view.window {
      if let found = TradeTraxsLaunchSplash.find(in: window) {
        TradeTraxsSplashDebugLog.line(
          "[tt-splash] dismissSplashOverlay REMOVE from view.window id=%@",
          String(describing: ObjectIdentifier(found))
        )
        found.removeFromSuperview()
      } else {
        TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay sweep view.window — none found")
      }
    } else {
      TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay sweep view.window — nil")
    }
    if let window = (UIApplication.shared.delegate as? AppDelegate)?.window {
      if let found = TradeTraxsLaunchSplash.find(in: window) {
        TradeTraxsSplashDebugLog.line(
          "[tt-splash] dismissSplashOverlay REMOVE from AppDelegate.window id=%@",
          String(describing: ObjectIdentifier(found))
        )
        found.removeFromSuperview()
      } else {
        TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay sweep AppDelegate.window — none found")
      }
    } else {
      TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay sweep AppDelegate.window — nil")
    }
    if let webView {
      if let found = TradeTraxsLaunchSplash.find(in: webView) {
        TradeTraxsSplashDebugLog.line(
          "[tt-splash] dismissSplashOverlay REMOVE from webView id=%@",
          String(describing: ObjectIdentifier(found))
        )
        found.removeFromSuperview()
      } else {
        TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay sweep webView — none found")
      }
    }

    logOverlayAudit(reason: "dismiss-completed")
    TradeTraxsSplashDebugLog.line("[tt-splash] dismissSplashOverlay COMPLETED splashDismissed=true")
  }

  /// TEMPORARY [tt-splash-debug] — hierarchy snapshot; no mutation.
  private func logOverlayAudit(reason: String) {
    let windows = UIApplication.shared.windows
    var anyOverlay = false
    for (i, w) in windows.enumerated() {
      let overlay = TradeTraxsLaunchSplash.find(in: w)
      if overlay != nil { anyOverlay = true }
      let wv = (w.rootViewController as? TradeTraxsBridgeViewController)?.webView
        ?? (w.rootViewController?.children.first as? TradeTraxsBridgeViewController)?.webView
      TradeTraxsSplashDebugLog.line(
        "[tt-splash] audit(%@) window[%ld] id=%@ key=%@ hidden=%@ level=%.1f overlay=%@ overlayHidden=%@ wvNil=%@ wvHidden=%@ wvAlpha=%.2f wvFrame=%@",
        reason,
        i,
        String(describing: ObjectIdentifier(w)),
        w.isKeyWindow ? "true" : "false",
        w.isHidden ? "true" : "false",
        w.windowLevel.rawValue,
        overlay != nil ? "true" : "false",
        overlay?.isHidden == true ? "true" : "false",
        wv == nil ? "true" : "false",
        wv?.isHidden == true ? "true" : "false",
        wv?.alpha ?? -1,
        wv.map { NSCoder.string(for: $0.frame) } ?? "nil"
      )
    }
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] audit(%@) summary anyOverlay=%@ splashDismissed=%@ splashOverlayRef=%@ windowCount=%ld sceneCount=%ld",
      reason,
      anyOverlay ? "true" : "false",
      splashDismissed ? "true" : "false",
      splashOverlay == nil ? "nil" : "set",
      windows.count,
      UIApplication.shared.connectedScenes.count
    )
  }

  // MARK: - URL persistence

  override open func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    if keyPath == #keyPath(WKWebView.url) {
      // TEMPORARY [tt-splash-debug]
      let url = (change?[.newKey] as? URL)?.absoluteString
        ?? webView?.url?.absoluteString
        ?? "nil"
      TradeTraxsSplashDebugLog.line(
        "[tt-splash] WKNavigation urlChanged url=%@ isLoading=%@ splashDismissed=%@",
        url,
        webView?.isLoading == true ? "true" : "false",
        splashDismissed ? "true" : "false"
      )
      persistWebViewUrl()
    } else if keyPath == #keyPath(WKWebView.isLoading) {
      // TEMPORARY [tt-splash-debug] — proxy for didStart/didFinish without replacing Cap's nav delegate.
      let loading = (change?[.newKey] as? Bool) ?? webView?.isLoading ?? false
      TradeTraxsSplashDebugLog.line(
        "[tt-splash] WKNavigation %@ url=%@ splashDismissed=%@ overlayPresent=%@",
        loading ? "START(isLoading=true)" : "FINISH(isLoading=false)",
        webView?.url?.absoluteString ?? "nil",
        splashDismissed ? "true" : "false",
        (view.window.flatMap { TradeTraxsLaunchSplash.find(in: $0) } != nil) ? "true" : "false"
      )
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

  private func startObservingLoading() {
    guard !observingLoading, let webView else { return }
    // TEMPORARY [tt-splash-debug]
    webView.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: [.new, .initial], context: nil)
    observingLoading = true
    TradeTraxsSplashDebugLog.line(
      "[tt-splash] WKNavigation observer installed isLoading=%@ url=%@",
      webView.isLoading ? "true" : "false",
      webView.url?.absoluteString ?? "nil"
    )
  }

  private func stopObservingLoading() {
    guard observingLoading, let webView else { return }
    webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
    observingLoading = false
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
