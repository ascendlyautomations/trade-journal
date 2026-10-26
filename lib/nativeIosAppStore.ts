/** Production App Store listing — keep in sync with `AppStoreProductReview.appStoreID`. */
export const NATIVE_IOS_APP_STORE_ID = "6808723069"

export function nativeIosAppStoreURL(): string {
  return `https://apps.apple.com/app/id${NATIVE_IOS_APP_STORE_ID}`
}

/** Smart App Banner (`apple-itunes-app`) for Universal Link landing pages. */
export function appleSmartAppBannerContent(appArgument: string): string {
  const trimmed = appArgument.trim()
  return `app-id=${NATIVE_IOS_APP_STORE_ID}, app-argument=${trimmed}`
}
