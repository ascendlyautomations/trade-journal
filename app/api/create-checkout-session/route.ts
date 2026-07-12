import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import { mirrorBillingAccountsStripeCustomerId } from "@/lib/profileSplitMirrorWrites"
import { ensureProfileForUser } from "@/lib/ensureProfileForUser"
import { createAffiliateReferralNotification, resolveAffiliateUserIdFromCode } from "@/lib/server/affiliateReferralNotifications"
import {
  ensureBuyerReferredBy,
  resolveAffiliateForCheckout,
} from "@/lib/affiliateCheckoutAttribution"
import {
  buildAffiliateAttributionMetadata,
} from "@/lib/affiliateStripeDiscount"
import { isProActive } from "@/lib/subscription"
import {
  parseCheckoutBillingInterval,
  resolveTraxProStripePriceId,
} from "@/lib/traxProBillingPlans.server"
import { devLog } from "@/lib/devLog"
import { resolveCheckoutTrialPeriodDays } from "@/lib/checkoutTrial"
import { toUserFacingErrorMessage, USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  try {
    devLog("🚀 /api/create-checkout-session hit")

    if (!process.env.STRIPE_SECRET_KEY) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE },
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
          devLog("❌ Bearer token auth failed for checkout:", tokenErr.message)
        } else if (tokenData.user) {
          user = tokenData.user
        }
      }
    }

    if (!user) {
      devLog(
        "❌ Unauthorized checkout attempt: no Supabase auth user in request cookies or bearer token"
      )
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }
    const userEmail = user.email ?? undefined

    let referralCodeFromBody: string | null = null
    let billingInterval = parseCheckoutBillingInterval(null)
    try {
      const body = await req.json()
      billingInterval = parseCheckoutBillingInterval(body)
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

    let stripePriceId: string
    try {
      stripePriceId = resolveTraxProStripePriceId(billingInterval)
    } catch (priceErr) {
      console.error("[api/create-checkout-session] price config", priceErr)
      return Response.json(
        { error: toUserFacingErrorMessage(priceErr, USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE) },
        { status: 500 }
      )
    }

    const { data: initialProfile, error: profileError } = await supabase
      .from("profiles")
      .select("id, stripe_customer_id, is_pro, subscription_status, referred_by, trial_end")
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
        .select("id, stripe_customer_id, referred_by, trial_end")
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
      devLog("🆕 Creating Stripe customer (no stripe_customer_id on profile)")

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
          devLog("✅ Saved stripe_customer_id to profile:", customerId)
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
      devLog("♻️ Reusing existing Stripe customer:", customerId)
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

    const existingReferredBy =
      profile && "referred_by" in profile
        ? (profile.referred_by as string | null | undefined)
        : null

    const affiliateForCheckout = await resolveAffiliateForCheckout(supabase, {
      buyerUserId: user.id,
      existingReferredBy,
      referralCodeFromBody,
    })


    if (affiliateForCheckout) {
      try {
        const attribution = await ensureBuyerReferredBy(supabase, {
          buyerUserId: user.id,
          affiliateCode: affiliateForCheckout.code,
          existingReferredBy,
        })
        if (attribution.newlySet) {
          try {
            await createAffiliateReferralNotification(supabase, {
              affiliateUserId: affiliateForCheckout.user_id,
              referredUserId: user.id,
            })
          } catch (notifErr) {
            console.error(
              "[create-checkout-session] affiliate referral notification failed:",
              notifErr
            )
          }
        }
      } catch (attrErr) {
        console.error(
          "[create-checkout-session] failed to persist referred_by:",
          attrErr
        )
      }
    }

    const attributionMeta = affiliateForCheckout
      ? buildAffiliateAttributionMetadata({
          affiliateUserId: affiliateForCheckout.user_id,
          affiliateCode: affiliateForCheckout.code,
          referredUserId: user.id,
        })
      : null

    if (affiliateForCheckout && attributionMeta && customerId) {
      try {
        await stripe.customers.update(customerId, {
          metadata: {
            user_id: user.id,
            ...attributionMeta,
          },
        })
      } catch (custMetaErr) {
        console.error(
          "[create-checkout-session] customer metadata update failed:",
          custMetaErr
        )
      }
    }

    const promoId = affiliateForCheckout?.stripe_promo_code_id?.trim() || null
    const applyAffiliateDiscount = Boolean(promoId)

    const trialPeriodDays = resolveCheckoutTrialPeriodDays({
      trial_end:
        profile && "trial_end" in profile
          ? (profile.trial_end as string | null | undefined)
          : null,
    })

    // Stripe-side guard: prior subscriptions that already used a trial.
    let effectiveTrialDays = trialPeriodDays
    if (effectiveTrialDays != null && customerId) {
      try {
        const priorSubs = await stripe.subscriptions.list({
          customer: customerId,
          status: "all",
          limit: 20,
        })
        const alreadyTrialed = priorSubs.data.some(
          (sub) => sub.trial_end != null
        )
        if (alreadyTrialed) {
          effectiveTrialDays = null
        }
      } catch (trialLookupErr) {
        console.error(
          "[create-checkout-session] prior trial lookup failed:",
          trialLookupErr
        )
      }
    }

    devLog("💳 Checkout config:", {
      priceId: stripePriceId,
      billingInterval,
      baseUrl,
      trialDays: effectiveTrialDays ?? 0,
      userId: user.id,
      affiliateCode: affiliateForCheckout?.code ?? null,
      applyAffiliateDiscount,
    })

    const sessionConfig: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      customer: customerId,
      payment_method_types: ["card"],
      ...(applyAffiliateDiscount
        ? {
            discounts: [{ promotion_code: promoId! }],
          }
        : {
            allow_promotion_codes: true,
          }),
      line_items: [
        {
          price: stripePriceId,
          quantity: 1,
        },
      ],
      success_url: `${baseUrl}/dashboard?checkout=success`,
      cancel_url: `${baseUrl}/finish-trial`,
      metadata: {
        user_id: user.id,
        userId: user.id,
        billing_interval: billingInterval,
        ...(attributionMeta ?? {}),
      },
      subscription_data: {
        ...(effectiveTrialDays != null
          ? { trial_period_days: effectiveTrialDays }
          : {}),
        metadata: {
          user_id: user.id,
          userId: user.id,
          billing_interval: billingInterval,
          ...(attributionMeta ?? {}),
        },
      },
    }

    const session = await stripe.checkout.sessions.create(sessionConfig)

    devLog("🔥 SESSION CREATED:", session.id, session.metadata)

    return Response.json({ url: session.url })
  } catch (err: unknown) {
    console.error("[api/create-checkout-session]", err)
    return Response.json(
      { error: toUserFacingErrorMessage(err, USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE) },
      { status: 500 }
    )
  }
}
