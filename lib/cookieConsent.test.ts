import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import {
  clearCookieConsent,
  COOKIE_CONSENT_STORAGE_KEY,
  hasCookieConsentChoice,
  isAnalyticsAllowed,
  readCookieConsent,
  saveCookieConsent,
} from "./cookieConsent.ts"

const localStorageMock = new Map<string, string>()

describe("cookieConsent", () => {
  beforeEach(() => {
    localStorageMock.clear()
    Object.defineProperty(globalThis, "window", {
      configurable: true,
      value: {
        localStorage: {
          getItem: (key: string) => localStorageMock.get(key) ?? null,
          setItem: (key: string, value: string) => {
            localStorageMock.set(key, value)
          },
          removeItem: (key: string) => {
            localStorageMock.delete(key)
          },
        },
      },
    })
    clearCookieConsent()
  })

  it("starts with no stored choice", () => {
    assert.equal(hasCookieConsentChoice(), false)
    assert.equal(readCookieConsent(), null)
  })

  it("stores accept-all with analytics enabled", () => {
    const record = saveCookieConsent("all")
    assert.equal(record.choice, "all")
    assert.equal(record.analytics, true)
    assert.equal(hasCookieConsentChoice(), true)
    assert.equal(isAnalyticsAllowed(), true)
    assert.equal(readCookieConsent()?.choice, "all")
  })

  it("stores essential-only with analytics disabled", () => {
    saveCookieConsent("essential")
    const record = readCookieConsent()
    assert.equal(record?.choice, "essential")
    assert.equal(record?.analytics, false)
    assert.equal(isAnalyticsAllowed(), false)
  })

  it("clearCookieConsent removes stored record", () => {
    saveCookieConsent("all")
    clearCookieConsent()
    assert.equal(localStorageMock.get(COOKIE_CONSENT_STORAGE_KEY), undefined)
  })
})
export {}
