/**
 * Production iOS application identity.
 *
 * Must stay identical across:
 * - Xcode PRODUCT_BUNDLE_IDENTIFIER
 * - Capacitor `appId`
 * - Info.plist CFBundleURLSchemes / CFBundleURLName
 * - APNs topic (APNS_BUNDLE_ID / default)
 * - Apple Developer App ID
 * - Future Sign in with Apple / Associated Domains bindings
 */
export const NATIVE_IOS_APP_ID = "com.tradetraxs.ios" as const

/** Custom URL scheme used for native OAuth return (same string as the App ID). */
export const NATIVE_IOS_URL_SCHEME = NATIVE_IOS_APP_ID
