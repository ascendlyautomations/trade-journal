import assert from "node:assert/strict"
import test from "node:test"
import {
  REFERRAL_CODE_STORAGE_KEY,
  REFERRAL_STORAGE_MAX_AGE_MS,
  clearStoredReferralCode,
  isStoredReferralExpired,
  parseStoredReferralValue,
  persistReferralCodeFromUrl,
  readStoredReferralCode,
} from "./referralPersistence.ts"

function installMemoryLocalStorage() {
  const store = new Map<string, string>()
  const localStorage = {
    getItem(key: string) {
      return store.has(key) ? store.get(key)! : null
    },
    setItem(key: string, value: string) {
      store.set(key, String(value))
    },
    removeItem(key: string) {
      store.delete(key)
    },
    clear() {
      store.clear()
    },
  }
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: localStorage,
  })
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: globalThis,
  })
  return store
}

test("parseStoredReferralValue accepts envelope and legacy bare strings", () => {
  assert.deepEqual(parseStoredReferralValue(null), { kind: "empty" })
  assert.deepEqual(parseStoredReferralValue("  "), { kind: "empty" })
  assert.deepEqual(parseStoredReferralValue("ABC123"), {
    kind: "legacy",
    code: "ABC123",
  })
  assert.deepEqual(
    parseStoredReferralValue(
      JSON.stringify({ v: 1, code: "XYZ999", storedAt: 1_700_000_000_000 })
    ),
    {
      kind: "record",
      record: { v: 1, code: "XYZ999", storedAt: 1_700_000_000_000 },
    }
  )
  assert.deepEqual(parseStoredReferralValue("{not-json"), {
    kind: "legacy",
    code: "{not-json",
  })
})

test("isStoredReferralExpired enforces the configured lifetime", () => {
  const storedAt = 1_700_000_000_000
  assert.equal(isStoredReferralExpired(storedAt, storedAt), false)
  assert.equal(
    isStoredReferralExpired(storedAt, storedAt + REFERRAL_STORAGE_MAX_AGE_MS),
    false
  )
  assert.equal(
    isStoredReferralExpired(
      storedAt,
      storedAt + REFERRAL_STORAGE_MAX_AGE_MS + 1
    ),
    true
  )
  assert.equal(isStoredReferralExpired(0, Date.now()), true)
})

test("persist + read round-trip stores a timestamped envelope", () => {
  const store = installMemoryLocalStorage()
  const code = persistReferralCodeFromUrl("?tab=signup&ref=AbC123")
  assert.equal(code, "AbC123")

  const raw = store.get(REFERRAL_CODE_STORAGE_KEY)
  assert.ok(raw)
  const envelope = JSON.parse(raw!) as {
    v: number
    code: string
    storedAt: number
  }
  assert.equal(envelope.v, 1)
  assert.equal(envelope.code, "AbC123")
  assert.ok(Number.isFinite(envelope.storedAt))

  assert.equal(readStoredReferralCode(), "AbC123")
})

test("expired browser referral is discarded without touching other systems", () => {
  const store = installMemoryLocalStorage()
  const old = Date.now() - REFERRAL_STORAGE_MAX_AGE_MS - 1_000
  store.set(
    REFERRAL_CODE_STORAGE_KEY,
    JSON.stringify({ v: 1, code: "STALE1", storedAt: old })
  )

  assert.equal(readStoredReferralCode(), null)
  assert.equal(store.has(REFERRAL_CODE_STORAGE_KEY), false)
})

test("clearStoredReferralCode removes browser state after attribution", () => {
  const store = installMemoryLocalStorage()
  persistReferralCodeFromUrl("?ref=KEEPME")
  assert.equal(readStoredReferralCode(), "KEEPME")

  clearStoredReferralCode()
  assert.equal(store.has(REFERRAL_CODE_STORAGE_KEY), false)
  assert.equal(readStoredReferralCode(), null)
})

test("legacy bare strings migrate once then expire on the TTL", () => {
  const store = installMemoryLocalStorage()
  store.set(REFERRAL_CODE_STORAGE_KEY, "LEGACY")

  const now = 2_000_000_000_000
  assert.equal(readStoredReferralCode(now), "LEGACY")

  const migrated = JSON.parse(store.get(REFERRAL_CODE_STORAGE_KEY)!) as {
    v: number
    code: string
    storedAt: number
  }
  assert.equal(migrated.v, 1)
  assert.equal(migrated.code, "LEGACY")
  assert.equal(migrated.storedAt, now)

  assert.equal(
    readStoredReferralCode(now + REFERRAL_STORAGE_MAX_AGE_MS + 1),
    null
  )
  assert.equal(store.has(REFERRAL_CODE_STORAGE_KEY), false)
})

test("beta invite codes are never kept in browser storage", () => {
  const store = installMemoryLocalStorage()
  assert.equal(persistReferralCodeFromUrl("?ref=TRAXBETA10302"), null)
  assert.equal(store.has(REFERRAL_CODE_STORAGE_KEY), false)

  store.set(REFERRAL_CODE_STORAGE_KEY, "TRAXBETA10302")
  assert.equal(readStoredReferralCode(), null)
  assert.equal(store.has(REFERRAL_CODE_STORAGE_KEY), false)
})
