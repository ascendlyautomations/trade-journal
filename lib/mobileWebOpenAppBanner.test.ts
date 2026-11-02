import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY,
  MOBILE_WEB_GET_APP_DISMISS_MS,
  appBannerNavbarShiftPx,
  configuredIosAppStoreUrl,
  dismissMobileWebGetAppBanner,
  isEmbeddedAppShell,
  isFullscreenMediaOpen,
  isMobileWebGetAppBannerDismissed,
  shouldShowMobileWebGetAppBanner,
} from "./mobileWebOpenAppBanner.ts"

describe("mobileWebGetAppBanner", () => {
  it("stays disabled until an official App Store URL is configured", () => {
    assert.equal(configuredIosAppStoreUrl(undefined), null)
    assert.equal(configuredIosAppStoreUrl("  "), null)
    assert.equal(configuredIosAppStoreUrl("https://apps.apple.com"), null)
    assert.equal(configuredIosAppStoreUrl("https://apps.apple.com/"), null)
    assert.equal(configuredIosAppStoreUrl("http://apps.apple.com/app/id1"), null)
    assert.equal(configuredIosAppStoreUrl("/app/id1"), null)
    assert.equal(configuredIosAppStoreUrl("https://example.com/app/id1"), null)
    assert.equal(
      configuredIosAppStoreUrl("https://user:pass@apps.apple.com/app/id1"),
      null
    )
    assert.equal(
      configuredIosAppStoreUrl("https://apps.apple.com/app/id6808723069"),
      "https://apps.apple.com/app/id6808723069"
    )
    assert.equal(
      configuredIosAppStoreUrl("https://itunes.apple.com/us/app/tradetraxs/id1"),
      "https://itunes.apple.com/us/app/tradetraxs/id1"
    )
  })

  it("hides a dismissal for 30 days and shows it again after that", () => {
    const store = new Map<string, string>()
    const storage = {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => {
        store.set(key, value)
      },
    }
    const now = 1_700_000_000_000
    assert.equal(isMobileWebGetAppBannerDismissed(storage, now), false)
    dismissMobileWebGetAppBanner(storage, now)
    assert.equal(store.get(MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY), String(now))
    assert.equal(isMobileWebGetAppBannerDismissed(storage, now + 1000), true)
    assert.equal(
      isMobileWebGetAppBannerDismissed(
        storage,
        now + MOBILE_WEB_GET_APP_DISMISS_MS - 1
      ),
      true
    )
    assert.equal(
      isMobileWebGetAppBannerDismissed(storage, now + MOBILE_WEB_GET_APP_DISMISS_MS),
      false
    )
    store.set(MOBILE_WEB_GET_APP_BANNER_STORAGE_KEY, "nope")
    assert.equal(isMobileWebGetAppBannerDismissed(storage, now), false)
  })

  it("shows only on phone web with a listing, outside native shells and fullscreen media", () => {
    const url = "https://apps.apple.com/app/id1"
    const ready = {
      appStoreUrl: url,
      dismissed: false,
      phoneWeb: true,
      embeddedShell: false,
      clipsImmersive: false,
      fullscreenMedia: false,
    }
    assert.equal(shouldShowMobileWebGetAppBanner(ready), true)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, appStoreUrl: null }), false)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, dismissed: true }), false)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, phoneWeb: false }), false)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, embeddedShell: true }), false)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, clipsImmersive: true }), false)
    assert.equal(shouldShowMobileWebGetAppBanner({ ...ready, fullscreenMedia: true }), false)
    assert.equal(
      isEmbeddedAppShell({
        htmlClassName: "tt-native tt-native-ios",
        userAgent: "Mozilla/5.0",
        hasCapacitor: false,
      }),
      true
    )
    assert.equal(
      isEmbeddedAppShell({
        htmlClassName: "",
        userAgent: "Mozilla/5.0 TradeTraxsNative",
        hasCapacitor: false,
      }),
      true
    )
    assert.equal(
      isEmbeddedAppShell({
        htmlClassName: "",
        userAgent: "Mozilla/5.0",
        hasCapacitor: true,
      }),
      true
    )
    assert.equal(
      isEmbeddedAppShell({
        htmlClassName: "",
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        hasCapacitor: false,
      }),
      false
    )
    assert.equal(
      isFullscreenMediaOpen({
        fullscreenElement: null,
        querySelector: () => null,
      }),
      false
    )
    assert.equal(
      isFullscreenMediaOpen({
        fullscreenElement: {},
        querySelector: () => null,
      }),
      true
    )
    assert.equal(
      isFullscreenMediaOpen({
        fullscreenElement: null,
        querySelector: (selector) => (selector.includes("Stories") ? {} : null),
      }),
      true
    )
  })

  it("lets the navbar rise as the banner scrolls away", () => {
    assert.equal(appBannerNavbarShiftPx(80, 0), 80)
    assert.equal(appBannerNavbarShiftPx(80, 30), 50)
    assert.equal(appBannerNavbarShiftPx(80, 80), 0)
    assert.equal(appBannerNavbarShiftPx(80, 200), 0)
    assert.equal(appBannerNavbarShiftPx(0, 0), 0)
  })
})
