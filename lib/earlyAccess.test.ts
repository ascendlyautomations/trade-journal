import assert from "node:assert/strict"
import test from "node:test"
import {
  buildEarlyAccessReferralLink,
  earlyAccessDaysRemaining,
  isEarlyAccessActive,
  shouldShowProForLifeCard,
} from "./earlyAccess.ts"
import { isProActive } from "./subscription.ts"

test("Early Access is active only with active status and a future end", () => {
  const future = new Date(Date.now() + 60_000).toISOString()
  const past = new Date(Date.now() - 60_000).toISOString()
  const enrollment = {
    early_access_enrolled_at: new Date().toISOString(),
    early_access_started_at: new Date().toISOString(),
    early_access_campaign_id: "traxs_pro_for_life_v1",
    early_access_enrollment_source: "standard_email",
  }

  assert.equal(
    isEarlyAccessActive({
      ...enrollment,
      early_access_status: "active",
      early_access_ends_at: future,
    }),
    true
  )
  assert.equal(
    isEarlyAccessActive({
      ...enrollment,
      early_access_status: "expired",
      early_access_ends_at: future,
    }),
    false
  )
  assert.equal(
    isEarlyAccessActive({
      ...enrollment,
      early_access_status: "active",
      early_access_ends_at: past,
    }),
    false
  )
})

test("central Pro helper recognizes only unexpired active Early Access", () => {
  const enrollment = {
    early_access_enrolled_at: new Date().toISOString(),
    early_access_started_at: new Date().toISOString(),
    early_access_campaign_id: "traxs_pro_for_life_v1",
    early_access_enrollment_source: "standard_oauth",
  }
  assert.equal(
    isProActive({
      ...enrollment,
      early_access_status: "active",
      early_access_ends_at: new Date(Date.now() + 60_000).toISOString(),
    }),
    true
  )
  assert.equal(
    isProActive({
      ...enrollment,
      early_access_status: "active",
      early_access_ends_at: new Date(Date.now() - 60_000).toISOString(),
    }),
    false
  )
})

test("Pro For Life card eligibility excludes existing access cohorts", () => {
  const enrolled = {
    onboarding_completed: true,
    early_access_enrolled_at: "2026-07-16T20:00:00.000Z",
    early_access_started_at: "2026-07-16T20:00:00.000Z",
    early_access_ends_at: "2026-08-06T20:00:00.000Z",
    early_access_status: "active",
    early_access_campaign_id: "traxs_pro_for_life_v1",
    early_access_enrollment_source: "standard_email",
  }

  assert.equal(shouldShowProForLifeCard({ ...enrolled, is_pro: true }), false)
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      subscription_status: "active",
      stripe_customer_id: "cus_paid",
    }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      subscription_status: "trialing",
      trial_end: "2026-07-30T20:00:00.000Z",
    }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({ ...enrolled, creator_access: true }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({ ...enrolled, is_beta_tester: true }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      lifetime_access_source: "legacy_lifetime",
    }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({
      onboarding_completed: true,
      use_free_tier: true,
    }),
    false
  )
})

test("card appears only for enrolled standard signups after onboarding", () => {
  const enrolled = {
    onboarding_completed: true,
    early_access_enrolled_at: "2026-07-16T20:00:00.000Z",
    early_access_started_at: "2026-07-16T20:00:00.000Z",
    early_access_ends_at: "2026-08-06T20:00:00.000Z",
    early_access_status: "active",
    early_access_campaign_id: "traxs_pro_for_life_v1",
  }

  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      early_access_enrollment_source: "standard_email",
    }),
    true
  )
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      early_access_enrollment_source: "standard_oauth",
    }),
    true
  )
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      early_access_enrollment_source: null,
      creator_access: true,
    }),
    false
  )
  assert.equal(
    shouldShowProForLifeCard({
      ...enrolled,
      onboarding_completed: false,
      early_access_enrollment_source: "standard_email",
    }),
    false
  )
})

test("referral links use the durable referral code and signup tab", () => {
  assert.equal(
    buildEarlyAccessReferralLink("ABC 123"),
    "https://tradetraxs.com/login?tab=signup&ref=ABC%20123"
  )
})

test("days remaining rounds partial days up and never goes negative", () => {
  const now = new Date("2026-07-16T12:00:00.000Z")
  assert.equal(earlyAccessDaysRemaining("2026-07-17T00:00:00.000Z", now), 1)
  assert.equal(earlyAccessDaysRemaining("2026-07-15T00:00:00.000Z", now), 0)
})
