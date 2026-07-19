import assert from "node:assert/strict"
import test from "node:test"
import {
  backfillReferredByIfMissing,
  normalizeReferralAttributionCode,
  type ReferralAttributionDb,
  type ReferralAttributionProfile,
} from "./referralAttribution.ts"

type StoredProfile = ReferralAttributionProfile

/**
 * In-memory double of the profiles table implementing the same set-once
 * semantics as the SQL conditional UPDATE (write only when referred_by
 * is NULL, predicate evaluated at write time).
 */
function createMemoryDb(profiles: Map<string, StoredProfile>): ReferralAttributionDb {
  return {
    async loadProfile(userId) {
      const row = profiles.get(userId)
      return row ? { ...row } : null
    },
    async countCodeOwners(code, excludeUserId) {
      let count = 0
      for (const row of profiles.values()) {
        if (row.id === excludeUserId) continue
        if (
          row.referral_code != null &&
          row.referral_code.trim().toUpperCase() === code
        ) {
          count += 1
        }
      }
      return count
    },
    async setReferredByIfNull(userId, code) {
      const row = profiles.get(userId)
      if (!row) return false
      if (row.referred_by != null) return false
      row.referred_by = code
      return true
    },
  }
}

function addProfile(
  profiles: Map<string, StoredProfile>,
  id: string,
  referralCode: string,
  referredBy: string | null = null
): void {
  profiles.set(id, { id, referral_code: referralCode, referred_by: referredBy })
}

function referralCreditFor(
  profiles: Map<string, StoredProfile>,
  inviterId: string
): number {
  const inviter = profiles.get(inviterId)
  if (!inviter?.referral_code) return 0
  const code = inviter.referral_code.trim().toUpperCase()
  let credit = 0
  for (const row of profiles.values()) {
    if (row.id === inviterId) continue
    if (
      row.referred_by != null &&
      row.referred_by.trim().toUpperCase() === code
    ) {
      credit += 1
    }
  }
  return credit
}

test("code normalization rejects beta, junk, and wildcard input", () => {
  assert.equal(normalizeReferralAttributionCode(" abc123 "), "ABC123")
  assert.equal(normalizeReferralAttributionCode(null), null)
  assert.equal(normalizeReferralAttributionCode(""), null)
  assert.equal(normalizeReferralAttributionCode("   "), null)
  assert.equal(normalizeReferralAttributionCode("TRAXBETA10302"), null)
  assert.equal(normalizeReferralAttributionCode("%"), null)
  assert.equal(normalizeReferralAttributionCode("AB%123"), null)
  assert.equal(normalizeReferralAttributionCode("A_C123"), null)
  assert.equal(normalizeReferralAttributionCode("AB"), null)
  assert.equal(
    normalizeReferralAttributionCode("X".repeat(21)),
    null
  )
})

test("referral chain A → B → C → D: every attribution lands exactly once", async () => {
  const profiles = new Map<string, StoredProfile>()
  const db = createMemoryDb(profiles)

  // A signed up organically; the rest were created as shells (referred_by
  // lost in the signup race) and are repaired via the backfill.
  addProfile(profiles, "user-a", "AAAAAA")
  addProfile(profiles, "user-b", "BBBBBB")
  addProfile(profiles, "user-c", "CCCCCC")
  addProfile(profiles, "user-d", "DDDDDD")

  assert.equal(
    await backfillReferredByIfMissing(db, "user-b", "AAAAAA"),
    "attributed"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "user-c", "bbbbbb"),
    "attributed"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "user-d", " CCCCCC "),
    "attributed"
  )

  // Everyone keeps their own referral code.
  assert.equal(profiles.get("user-a")?.referral_code, "AAAAAA")
  assert.equal(profiles.get("user-b")?.referral_code, "BBBBBB")
  assert.equal(profiles.get("user-c")?.referral_code, "CCCCCC")
  assert.equal(profiles.get("user-d")?.referral_code, "DDDDDD")

  // Correct inviter recorded on each account.
  assert.equal(profiles.get("user-b")?.referred_by, "AAAAAA")
  assert.equal(profiles.get("user-c")?.referred_by, "BBBBBB")
  assert.equal(profiles.get("user-d")?.referred_by, "CCCCCC")

  // Each inviter receives exactly one credit under the challenge counting rule.
  assert.equal(referralCreditFor(profiles, "user-a"), 1)
  assert.equal(referralCreditFor(profiles, "user-b"), 1)
  assert.equal(referralCreditFor(profiles, "user-c"), 1)
  assert.equal(referralCreditFor(profiles, "user-d"), 0)
})

test("existing referral relationships are never overwritten", async () => {
  const profiles = new Map<string, StoredProfile>()
  const db = createMemoryDb(profiles)
  addProfile(profiles, "inviter-1", "INV111")
  addProfile(profiles, "inviter-2", "INV222")
  addProfile(profiles, "invitee", "MEMEME", "INV111")

  assert.equal(
    await backfillReferredByIfMissing(db, "invitee", "INV222"),
    "already_set"
  )
  assert.equal(profiles.get("invitee")?.referred_by, "INV111")
})

test("retries and concurrent backfills write exactly once", async () => {
  const profiles = new Map<string, StoredProfile>()
  const db = createMemoryDb(profiles)
  addProfile(profiles, "inviter", "INV111")
  addProfile(profiles, "other", "OTHER1")
  addProfile(profiles, "invitee", "MEMEME")

  const [first, second] = await Promise.all([
    backfillReferredByIfMissing(db, "invitee", "INV111"),
    backfillReferredByIfMissing(db, "invitee", "OTHER1"),
  ])
  const results = [first, second].sort()
  assert.deepEqual(results, ["already_set", "attributed"])

  // Retry after success is idempotent.
  assert.equal(
    await backfillReferredByIfMissing(db, "invitee", "INV111"),
    "already_set"
  )

  const stored = profiles.get("invitee")?.referred_by
  assert.ok(stored === "INV111" || stored === "OTHER1")
  assert.equal(
    referralCreditFor(profiles, "inviter") +
      referralCreditFor(profiles, "other"),
    1
  )
})

test("self-referral, unknown codes, and missing profiles are rejected", async () => {
  const profiles = new Map<string, StoredProfile>()
  const db = createMemoryDb(profiles)
  addProfile(profiles, "user", "MYCODE")

  assert.equal(
    await backfillReferredByIfMissing(db, "user", "MYCODE"),
    "invalid_code"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "user", "NOOWNER"),
    "invalid_code"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "user", null),
    "no_code"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "user", "TRAXBETA10302"),
    "no_code"
  )
  assert.equal(
    await backfillReferredByIfMissing(db, "ghost", "MYCODE"),
    "profile_missing"
  )
  assert.equal(profiles.get("user")?.referred_by, null)
})
