const assert = require("node:assert/strict")
const { describe, it, beforeEach } = require("node:test")

const localStorageMock = new Map()

describe("cookieConsent", () => {
  beforeEach(() => {
    localStorageMock.clear()
    Object.defineProperty(globalThis, "window", {
      configurable: true,
      value: {
        localStorage: {
          getItem: (key) => localStorageMock.get(key) ?? null,
          setItem: (key, value) => {
            localStorageMock.set(key, value)
          },
          removeItem: (key) => {
            localStorageMock.delete(key)
          },
        },
      },
    })
    const {
      clearCookieConsent,
    } = require("./cookieConsent.ts")
    clearCookieConsent()
  })

  it("starts with no stored choice", () => {
    const {
      hasCookieConsentChoice,
      readCookieConsent,
    } = require("./cookieConsent.ts")
    assert.equal(hasCookieConsentChoice(), false)
    assert.equal(readCookieConsent(), null)
  })

  it("stores accept-all with analytics enabled", () => {
    const {
      hasCookieConsentChoice,
      isAnalyticsAllowed,
      readCookieConsent,
      saveCookieConsent,
    } = require("./cookieConsent.ts")
    const record = saveCookieConsent("all")
    assert.equal(record.choice, "all")
    assert.equal(record.analytics, true)
    assert.equal(hasCookieConsentChoice(), true)
    assert.equal(isAnalyticsAllowed(), true)
    assert.equal(readCookieConsent()?.choice, "all")
  })

  it("stores essential-only with analytics disabled", () => {
    const {
      isAnalyticsAllowed,
      readCookieConsent,
      saveCookieConsent,
    } = require("./cookieConsent.ts")
    saveCookieConsent("essential")
    const record = readCookieConsent()
    assert.equal(record?.choice, "essential")
    assert.equal(record?.analytics, false)
    assert.equal(isAnalyticsAllowed(), false)
  })

  it("clearCookieConsent removes stored record", () => {
    const {
      COOKIE_CONSENT_STORAGE_KEY,
      clearCookieConsent,
      saveCookieConsent,
    } = require("./cookieConsent.ts")
    saveCookieConsent("all")
    clearCookieConsent()
    assert.equal(localStorageMock.get(COOKIE_CONSENT_STORAGE_KEY), undefined)
  })
})
