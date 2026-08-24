import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveEarlyAccessEnvironment } from "@/lib/earlyAccessEnvironment.server"
import type { TableUpdate } from "@/lib/supabaseTypes"
import {
  EARLY_ACCESS_DURATION_DAYS,
  generateEarlyAccessReferralCode,
} from "@/lib/earlyAccess"
import {
  backfillReferredByIfMissing,
  createSupabaseReferralAttributionDb,
} from "@/lib/referralAttribution"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const body = (await req.json().catch(() => null)) as {
    source?: unknown
  } | null
  const source =
    body?.source === "standard_email" || body?.source === "standard_oauth"
      ? body.source
      : null
  if (!source) {
    return Response.json({ result: "ineligible" }, { status: 400 })
  }

  const authProvider = String(user.app_metadata?.provider ?? "").toLowerCase()
  const providerMatchesSource =
    (source === "standard_email" &&
      (authProvider === "email" || authProvider === "")) ||
    (source === "standard_oauth" &&
      authProvider !== "" &&
      authProvider !== "email")
  const authCreatedAt = new Date(user.created_at).getTime()
  if (
    !providerMatchesSource ||
    !Number.isFinite(authCreatedAt) ||
    Date.now() - authCreatedAt > 15 * 60 * 1000
  ) {
    console.error("[early-access/enroll] rejected before RPC", {
      userId: user.id,
      source,
      authProvider,
      ageMs: Date.now() - authCreatedAt,
    })
    return Response.json({ result: "ineligible" }, { status: 403 })
  }

  // Auth triggers often create the profile shell before the client can stamp
  // signup_flow_source / referral_code. Prep those with the service role so the
  // enrollment RPC can accept the brand-new standard signup.
  const { data: profile, error: profileError } = await supabaseServiceRole
    .from("profiles")
    .select(
      "id, created_at, signup_flow_source, referral_code, referred_by, early_access_status, early_access_enrolled_at, early_access_started_at, early_access_ends_at, is_pro, creator_access, is_beta_tester, use_free_tier, stripe_customer_id, subscription_status, trial_end, lifetime_access_source"
    )
    .eq("id", user.id)
    .maybeSingle()

  if (profileError) {
    console.error("[early-access/enroll] profile load failed", profileError)
    return Response.json(
      { error: "Could not enroll this account in Early Access." },
      { status: 500 }
    )
  }

  if (!profile) {
    console.error("[early-access/enroll] profile missing", { userId: user.id })
    return Response.json({ result: "ineligible" }, { status: 403 })
  }

  const prep: TableUpdate<"profiles"> = {}
  if (
    profile.signup_flow_source == null ||
    String(profile.signup_flow_source).trim() === ""
  ) {
    prep.signup_flow_source = source
  } else if (profile.signup_flow_source !== source) {
    console.error("[early-access/enroll] signup_flow_source mismatch", {
      userId: user.id,
      source,
      signup_flow_source: profile.signup_flow_source,
    })
    return Response.json({ result: "ineligible" }, { status: 403 })
  }
  if (
    profile.referral_code == null ||
    String(profile.referral_code).trim() === ""
  ) {
    prep.referral_code = generateEarlyAccessReferralCode()
  }

  if (Object.keys(prep).length > 0) {
    const { error: prepError } = await supabaseServiceRole
      .from("profiles")
      .update(prep)
      .eq("id", user.id)
    if (prepError) {
      console.error("[early-access/enroll] profile prep failed", prepError)
      return Response.json(
        { error: "Could not enroll this account in Early Access." },
        { status: 500 }
      )
    }
  }

  // Auth triggers can create the shell before the client insert that carries
  // referral attribution. Restore referred_by (set-once, never overwrites)
  // from the code stamped into auth metadata at signup. Non-fatal.
  if (
    profile.referred_by == null ||
    String(profile.referred_by).trim() === ""
  ) {
    try {
      const attribution = await backfillReferredByIfMissing(
        createSupabaseReferralAttributionDb(supabaseServiceRole),
        user.id,
        user.user_metadata?.referral_code
      )
      if (attribution === "error") {
        console.error("[early-access/enroll] referred_by backfill failed", {
          userId: user.id,
        })
      }
    } catch (attributionError) {
      console.error(
        "[early-access/enroll] referred_by backfill threw",
        attributionError
      )
    }
  }

  const { data, error } = await supabaseServiceRole.rpc("enroll_early_access", {
    p_user_id: user.id,
    p_environment: resolveEarlyAccessEnvironment(),
    p_enrollment_source: source,
  })

  if (error) {
    console.error("[early-access/enroll]", error)
    return Response.json(
      { error: "Could not enroll this account in Early Access." },
      { status: 500 }
    )
  }

  const result = String(data ?? "ineligible")
  if (result === "enrolled" || result === "already_enrolled") {
    // Normalize complimentary window to 21 days even if an older RPC still
    // writes a 14-day interval until the additive migration is applied.
    const { data: enrolledRow, error: enrolledReadError } =
      await supabaseServiceRole
        .from("profiles")
        .select("early_access_started_at, early_access_ends_at")
        .eq("id", user.id)
        .maybeSingle()

    if (enrolledReadError) {
      console.error(
        "[early-access/enroll] post-enroll read failed",
        enrolledReadError
      )
    } else if (enrolledRow?.early_access_started_at) {
      const startedAt = new Date(enrolledRow.early_access_started_at)
      if (!Number.isNaN(startedAt.getTime())) {
        const expectedEndsAt = new Date(
          startedAt.getTime() +
            EARLY_ACCESS_DURATION_DAYS * 24 * 60 * 60 * 1000
        ).toISOString()
        if (enrolledRow.early_access_ends_at !== expectedEndsAt) {
          const { error: normalizeError } = await supabaseServiceRole
            .from("profiles")
            .update({ early_access_ends_at: expectedEndsAt })
            .eq("id", user.id)
          if (normalizeError) {
            console.error(
              "[early-access/enroll] duration normalize failed",
              normalizeError
            )
          }
        }
      }
    }
  } else if (process.env.NODE_ENV !== "production") {
    console.error("[early-access/enroll] RPC returned non-success", {
      userId: user.id,
      source,
      result,
    })
  }

  return Response.json({ result })
}
