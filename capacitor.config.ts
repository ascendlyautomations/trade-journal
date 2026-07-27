import type { CapacitorConfig } from '@capacitor/cli'
import { KeyboardResize, KeyboardStyle } from '@capacitor/keyboard'
import { resolveDevServerLanHost } from './lib/devServerLanHost'

/**
 * Hosted WebView architecture.
 * The Next.js app on Vercel remains the source of truth.
 * Capacitor loads that site in a native shell — it does not bundle the app.
 *
 * Cold start: server.url is the site origin; middleware sends native `/` → /native
 * (auth → dashboard, else → login). Web marketing homepage `/` is unchanged.
 *
 * CAPACITOR_ENV=production → https://www.tradetraxs.com
 * otherwise (default)      → http://<LAN-IP>:3000
 *   Override host with CAPACITOR_DEV_HOST when needed.
 */

const isProduction = process.env.CAPACITOR_ENV === 'production'

const devServerHost = isProduction
  ? null
  : resolveDevServerLanHost() ?? 'localhost'
// Origin only (no /native path). Capacitor treats server.url as a prefix for
// in-app navigations; a /native suffix made sibling routes look "external" and
// amplified resume remounts back through the cold-start redirect.
// Cold start still enters /native via middleware (native UA / tt_native cookie).
const appOrigin = isProduction
  ? 'https://www.tradetraxs.com'
  : `http://${devServerHost}:3000`

const config: CapacitorConfig = {
  // Must match Xcode PRODUCT_BUNDLE_IDENTIFIER and lib/nativeIosIdentity.ts
  appId: 'com.tradetraxs.ios',
  appName: 'TradeTraxs',
  // Stub directory required by Capacitor sync. Not the application bundle.
  webDir: 'www',
  // Native WKWebView background — matches navbar so paint gaps, overscroll
  // rubber-banding, and route transitions never expose a white surface.
  backgroundColor: '#0b1f3a',
  server: {
    url: appOrigin,
    // Required for http:// LAN / localhost during development.
    cleartext: !isProduction,
    // Keep same-site navigations inside the WebView (do not open Safari).
    allowNavigation: [
      'localhost',
      '127.0.0.1',
      ...(devServerHost &&
      devServerHost !== 'localhost' &&
      devServerHost !== '127.0.0.1'
        ? [devServerHost]
        : []),
      'www.tradetraxs.com',
      'tradetraxs.com',
    ],
  },
  plugins: {
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#0b1f3a',
      overlaysWebView: false,
    },
    Keyboard: {
      // Body-only resize keeps fixed chrome (navbar) stable; native resize
      // shrinks the WebView and makes vh / fixed headers jump.
      resize: KeyboardResize.Body,
      style: KeyboardStyle.Dark,
      // Tint the area behind the keyboard with backgroundColor (#0b1f3a).
      autoBackdropColor: 'auto',
    },
    // Foreground presentation: badge only (in-app UI + Navbar already refresh).
    // Background / quit: iOS still shows the APNs alert + sound from the payload.
    PushNotifications: {
      presentationOptions: ['badge'],
    },
  },
  ios: {
    // Capacitor 8 supports iOS 14+; lock an explicit floor for consistency.
    minVersion: '15.0',
    // CSS env(safe-area-inset-*) owns insets. `automatic` double-applies
    // WKWebView content insets on top of CSS and shifts fixed chrome.
    contentInset: 'never',
  },
  // Lets the web layer detect the Capacitor shell without waiting on the bridge.
  appendUserAgent: ' TradeTraxsNative/1',
}

export default config
