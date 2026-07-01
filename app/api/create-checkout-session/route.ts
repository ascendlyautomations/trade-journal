import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import { mirrorBillingAccountsStripeCustomerId } from "@/lib/profileSplitMirrorWrites"
import { ensureProfileForUser } from "@/lib/ensureProfileForUser"
import { createAffiliateReferralNotification, resolveAffiliateUserIdFromCode } from "@/lib/server/affiliateReferralNotifications"
import { isProActive } from "@/lib/subscription"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)
const STRIPE_PRICE_ID =
  process.env.STRIPE_PRICE_ID || "price_1TOWLoFtHxLxKCWEtD6AhvDl"
let TRIAL_DAYS = Number(process.env.STRIPE_TRIAL_DAYS ?? 14)
if (Number.isNaN(TRIAL_DAYS) || TRIAL_DAYS < 0) {
  TRIAL_DAYS = 14
}
console.log("[Stripe] Trial days:", TRIAL_DAYS)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  try {
    console.log("🚀 /api/create-checkout-session hit")

    if (!process.env.STRIPE_SECRET_KEY) {
      return Response.json(
        { error: "Missing STRIPE_SECRET_KEY" },
        { status: 500 }
      )
    }

    const cookieStore = await cookies()
    const supabaseAuth = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get: (name) => cookieStore.get(name)?.value,
        },
      }
    )

    const {
      data: { user: cookieUser },
    } = await supabaseAuth.auth.getUser()

    let user = cookieUser

    // Fallback for post-login race conditions where auth cookies are not yet
    // attached to this request; still requires a valid Supabase bearer token.
    if (!user) {
      const authHeader = req.headers.get("authorization") || ""
      const bearer = authHeader.startsWith("Bearer ")
        ? authHeader.slice("Bearer ".length).trim()
        : ""

      if (bearer) {
        const { data: tokenData, error: tokenErr } = await supabase.auth.getUser(
          bearer
        )
        if (tokenErr) {
          console.log("❌ Bearer token auth failed for checkout:", tokenErr.message)
        } else if (tokenData.user) {
          user = tokenData.user
        }
      }
    }

    if (!user) {
      console.log(
        "❌ Unauthorized checkout attempt: no Supabase auth user in request cookies or bearer token"
      )
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }
    const userEmail = user.email ?? undefined

    let referralCodeFromBody: string | null = null
    try {
      const body = await req.json()
      const raw =
        body && typeof body === "object" && "referralCode" in body
          ? body.referralCode
          : null
      if (raw != null && String(raw).trim()) {
        referralCodeFromBody = String(raw).trim()
      }
    } catch {
      /* empty body is fine */
    }

    const { data: initialProfile, error: profileError } = await supabase
      .from("profiles")
      .select("id, stripe_customer_id, is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()

    if (profileError) {
      console.error("ERROR:", JSON.stringify(profileError, null, 2))
      return Response.json(
        { error: "Could not load profile" },
        { status: 500 }
      )
    }

    let profile = initialProfile

    if (profile && isProActive(profile)) {
      return Response.json(
        { error: "You already have an active subscription." },
        { status: 409 }
      )
    }

    if (!profile) {
      const ensureResult = await ensureProfileForUser(supabase, {
        userId: user.id,
        referredBy: referralCodeFromBody,
        userMetadata: user.user_metadata,
      })

      if (!ensureResult.ok) {
        console.error(
          "ERROR:",
          JSON.stringify(ensureResult.error ?? { message: "ensure failed" }, null, 2)
        )
        return Response.json(
          { error: "Could not create profile" },
          { status: 500 }
        )
      }

      if (ensureResult.created && referralCodeFromBody?.trim()) {
        try {
          const affiliateUserId = await resolveAffiliateUserIdFromCode(
            supabase,
            referralCodeFromBody
          )
          if (affiliateUserId && affiliateUserId !== user.id) {
            await createAffiliateReferralNotification(supabase, {
              affiliateUserId,
              referredUserId: user.id,
            })
          }
        } catch (notifErr) {
          console.error("[create-checkout-session] affiliate referral notification failed:", notifErr)
        }
      }

      const refetch = await supabase
        .from("profiles")
        .select("id, stripe_customer_id")
        .eq("id", user.id)
        .maybeSingle()

      profile = refetch.data
      if (refetch.error) {
        console.error("ERROR:", JSON.stringify(refetch.error, null, 2))
        return Response.json(
          { error: "Could not load profile" },
          { status: 500 }
        )
      }
    }

    let customerId = profile?.stripe_customer_id as string | null | undefined

    if (!customerId) {
      console.log("🆕 Creating Stripe customer (no stripe_customer_id on profile)")

      try {
        const customer = await stripe.customers.create({
          email: userEmail,
          metadata: {
            user_id: user.id,
          },
        })

        customerId = customer.id

        const { error: updateErr } = await supabase
          .from("profiles")
          .update({ stripe_customer_id: customerId })
          .eq("id", user.id)

        if (updateErr) {
          console.error("ERROR:", JSON.stringify(updateErr, null, 2))
        } else {
          console.log("✅ Saved stripe_customer_id to profile:", customerId)
          const { error: mirrorErr } = await mirrorBillingAccountsStripeCustomerId(
            supabase,
            user.id,
            customerId
          )
          if (mirrorErr) {
            console.error(
              "mirror billing_accounts.stripe_customer_id:",
              JSON.stringify(mirrorErr, null, 2)
            )
          }
        }
      } catch (stripeErr) {
        console.error(
          "ERROR:",
          JSON.stringify(
            stripeErr instanceof Error
              ? { message: stripeErr.message, name: stripeErr.name }
              : stripeErr,
            null,
            2
          )
        )
        return Response.json(
          { error: "Could not create Stripe customer" },
          { status: 500 }
        )
      }
    } else {
      console.log("♻️ Reusing existing Stripe customer:", customerId)
    }

    if (!customerId) {
      console.error("ERROR:", JSON.stringify({ message: "Missing customer id" }, null, 2))
      return Response.json(
        { error: "Stripe customer unavailable" },
        { status: 500 }
      )
    }

    const baseUrl =
      process.env.NEXT_PUBLIC_BASE_URL?.trim() || new URL(req.url).origin

    console.log("💳 Checkout config:", {
      priceId: STRIPE_PRICE_ID,
      baseUrl,
      trialDays: TRIAL_DAYS,
      userId: user.id,
    })

    const sessionConfig: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      customer: customerId,
      payment_method_types: ["card"],
      allow_promotion_codes: true,
      line_items: [
        {
          price: STRIPE_PRICE_ID,
          quantity: 1,
        },
      ],
      success_url: `${baseUrl}/dashboard?checkout=success`,
      cancel_url: `${baseUrl}/?checkout=cancelled`,
      metadata: {
        user_id: user.id,
        userId: user.id,
      },
      subscription_data: {
        trial_period_days: TRIAL_DAYS,
        metadata: {
          user_id: user.id,
          userId: user.id,
        },
      },
    }

    const session = await stripe.checkout.sessions.create(sessionConfig)

    console.log("🔥 SESSION CREATED:", session.id, session.metadata)

    return Response.json({ url: session.url })
  } catch (err: unknown) {
    console.error(
      "ERROR:",
      JSON.stringify(
        err instanceof Error
          ? { message: err.message, name: err.name }
          : err,
        null,
        2
      )
    )
    const message = err instanceof Error ? err.message : "Stripe failed"
    return Response.json({ error: message }, { status: 500 })
  }
}
