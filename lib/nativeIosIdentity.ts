/**
 * Production iOS application identity — native Swift app is the single source of truth.
 *
 * Must stay identical across:
 * - Xcode PRODUCT_BUNDLE_IDENTIFIER (`native-ios/TradeTraxs`)
 * - APNs topic (`APNS_BUNDLE_ID` / default)
 * - Apple Developer App ID
 * - Apple App Site Association `appID`
 *
 * Custom URL scheme is registered separately in Info.plist (`tradetraxs`) and is
 * intentionally not required to equal the bundle identifier.
 */
export const NATIVE_IOS_APP_ID = "com.tradetraxs.TradeTraxs" as const

/** Custom URL scheme from native Info.plist / OAuth return path. */
export const NATIVE_IOS_URL_SCHEME = "tradetraxs" as const
