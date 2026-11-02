import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  MOBILE_WEB_GET_APP_BANNER_IMPRESSION_SESSION_KEY,
  appStoreClickProperties,
  markGetAppBannerImpressionSent,
  mobileWebAppInstallAnalyticsContext,
  openInAppClickProperties,
  shouldFireGetAppBannerImpression,
  shouldSendMobileWebAppInstallAnalytics,
} from "./mobileWebAppInstallAnalytics.ts"

describe("mobileWebAppInstallAnalytics", () => {
  it("gates on phone web, consent, and embedded shell", () => {
    assert.equal(
      shouldSendMobileWebAppInstallAnalytics({
        phoneWeb: true,
        embeddedShell: false,
        analyticsAllowed: true,
      }),
      true
    )
    assert.equal(
      shouldSendMobileWebAppInstallAnalytics({
        phoneWeb: false,
        embeddedShell: false,
        analyticsAllowed: true,
      }),
      false
    )
    assert.equal(
      shouldSendMobileWebAppInstallAnalytics({
        phoneWeb: true,
        embeddedShell: true,
        analyticsAllowed: true,
      }),
      false
    )
    assert.equal(
      shouldSendMobileWebAppInstallAnalytics({
        phoneWeb: true,
        embeddedShell: false,
        analyticsAllowed: false,
      }),
      false
    )
  })

  it("dedupes banner impressions per session store", () => {
    const store = new Map<string, string>()
    const session = {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => {
        store.set(key, value)
      },
    }
    assert.equal(shouldFireGetAppBannerImpression(session), true)
    markGetAppBannerImpressionSent(session)
    assert.equal(shouldFireGetAppBannerImpression(session), false)
    assert.equal(
      store.get(MOBILE_WEB_GET_APP_BANNER_IMPRESSION_SESSION_KEY),
      "1"
    )
  })

  it("uses coarse enums only in event payloads", () => {
    assert.deepEqual(
      openInAppClickProperties({ contentKind: "trade", uiVariant: "bar" }),
      { content_kind: "trade", ui_variant: "bar" }
    )
    assert.deepEqual(appStoreClickProperties({ surface: "open_in_app" }), {
      surface: "open_in_app",
    })
    const payload = JSON.stringify(
      openInAppClickProperties({ contentKind: "clip", uiVariant: "overlay" })
    )
    assert.equal(payload.includes("reel"), false)
    assert.equal(payload.includes("http"), false)
  })

  it("derives canSend from explicit context input", () => {
    const ctx = mobileWebAppInstallAnalyticsContext({
      phoneWeb: true,
      analyticsAllowed: true,
      htmlClassName: "",
      userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      hasCapacitor: false,
    })
    assert.equal(ctx.canSend, true)
  })
})
