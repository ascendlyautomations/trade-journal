import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  canonicalMobileWebOpenAppURL,
  dismissMobileWebOpenAppBanner,
  isIosSafariMobileUserAgent,
  isMobileWebOpenAppBannerDismissed,
  MOBILE_WEB_OPEN_APP_BANNER_SESSION_KEY,
} from "./mobileWebOpenAppBanner.ts"

describe("mobileWebOpenAppBanner", () => {
  it("uses the canonical https universal link", () => {
    assert.equal(
      canonicalMobileWebOpenAppURL("/trade/abc", "?ref=1"),
      "https://www.tradetraxs.com/trade/abc?ref=1"
    )
    assert.equal(
      canonicalMobileWebOpenAppURL("profile/nrl"),
      "https://www.tradetraxs.com/profile/nrl"
    )
  })

  it("shows only for mobile Safari, not the native shell", () => {
    assert.equal(
      isIosSafariMobileUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
      ),
      true
    )
    assert.equal(
      isIosSafariMobileUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) TradeTraxsNative"
      ),
      false
    )
    assert.equal(
      isIosSafariMobileUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"),
      false
    )
  })

  it("remembers dismissal in the provided session store", () => {
    const store = new Map<string, string>()
    const storage = {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => {
        store.set(key, value)
      },
    }
    assert.equal(isMobileWebOpenAppBannerDismissed(storage), false)
    dismissMobileWebOpenAppBanner(storage)
    assert.equal(store.get(MOBILE_WEB_OPEN_APP_BANNER_SESSION_KEY), "1")
    assert.equal(isMobileWebOpenAppBannerDismissed(storage), true)
  })
})
