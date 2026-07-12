/**
 * Migrate existing affiliate promotion codes from forever coupons to the shared
 * 10%-off-once coupon, preserving customer-facing codes.
 *
 * Does NOT modify live customer subscriptions that already have a forever
 * discount attached — those keep their existing Stripe subscription discount.
 *
 * Usage (dry run default):
 *   node scripts/migrate-affiliate-promos-to-once.mjs
 * Apply:
 *   node scripts/migrate-affiliate-promos-to-once.mjs --apply
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import Stripe from "stripe"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const idx = trimmed.indexOf("=")
    if (idx === -1) continue
    env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim()
  }
  return env
}

const env = loadEnv()
const apply = process.argv.includes("--apply")

const stripe = new Stripe(env.STRIPE_SECRET_KEY)
const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
)

const COUPON_NAME = "TradeTraxs Affiliate 10% Once"
const PURPOSE = "affiliate_first_invoice_discount"

async function ensureOnceCoupon() {
  if (env.STRIPE_AFFILIATE_ONCE_COUPON_ID) {
    const c = await stripe.coupons.retrieve(env.STRIPE_AFFILIATE_ONCE_COUPON_ID)
    if (c.valid && c.duration === "once" && Number(c.percent_off) === 10) {
      return c
    }
  }

  const listed = await stripe.coupons.list({ limit: 100 })
  for (const c of listed.data) {
    if (
      c.valid &&
      c.duration === "once" &&
      Number(c.percent_off) === 10 &&
      (c.metadata?.tradetraxs_purpose === PURPOSE || c.name === COUPON_NAME)
    ) {
      return c
    }
  }

  if (!apply) {
    console.log("[dry-run] would create coupon:", COUPON_NAME)
    return { id: "dry_run_coupon", duration: "once", percent_off: 10 }
  }

  return stripe.coupons.create({
    percent_off: 10,
    duration: "once",
    name: COUPON_NAME,
    metadata: {
      tradetraxs_purpose: PURPOSE,
      percent_off: "10",
      duration: "once",
    },
  })
}

async function couponDurationForPromo(promoId) {
  try {
    const promo = await stripe.promotionCodes.retrieve(promoId, {
      expand: ["promotion.coupon"],
    })
    const promotion = promo.promotion
    let coupon = null
    if (promotion && typeof promotion === "object") {
      if (typeof promotion.coupon === "object" && promotion.coupon) {
        coupon = promotion.coupon
      } else if (typeof promotion.coupon === "string") {
        coupon = await stripe.coupons.retrieve(promotion.coupon)
      }
    }
    // Legacy shape fallback
    if (!coupon && promo.coupon) {
      coupon =
        typeof promo.coupon === "object"
          ? promo.coupon
          : await stripe.coupons.retrieve(String(promo.coupon))
    }
    if (!coupon) {
      return { error: "coupon missing on promotion code", promo }
    }
    return {
      promo,
      couponId: coupon.id,
      duration: coupon.duration,
      percent_off: coupon.percent_off,
      active: promo.active,
      code: promo.code,
    }
  } catch (e) {
    return { error: e.message }
  }
}

const coupon = await ensureOnceCoupon()
console.log("Once coupon:", coupon.id, {
  duration: coupon.duration,
  percent_off: coupon.percent_off,
})

const { data: affiliates, error } = await supabase
  .from("affiliates")
  .select("user_id, code, stripe_promo_code_id")

if (error) throw error

console.log(`Found ${affiliates?.length ?? 0} affiliates. apply=${apply}`)

for (const row of affiliates ?? []) {
  const code = String(row.code || "").trim().toUpperCase()
  const existingPromoId = row.stripe_promo_code_id
    ? String(row.stripe_promo_code_id).trim()
    : null

  const info = existingPromoId
    ? await couponDurationForPromo(existingPromoId)
    : null

  console.log("\n—", code, {
    user_id: row.user_id,
    existingPromoId,
    current: info,
  })

  if (info && !info.error && info.duration === "once" && Number(info.percent_off) === 10) {
    console.log("  already on once/10% — skip")
    continue
  }

  if (!apply) {
    console.log("  [dry-run] would deactivate old promo and create once promo for", code)
    continue
  }

  if (existingPromoId) {
    try {
      await stripe.promotionCodes.update(existingPromoId, { active: false })
      console.log("  deactivated", existingPromoId)
    } catch (e) {
      console.warn("  deactivate failed:", e.message)
    }
  }

  const activeSameCode = await stripe.promotionCodes.list({
    code,
    active: true,
    limit: 10,
  })
  for (const p of activeSameCode.data) {
    await stripe.promotionCodes.update(p.id, { active: false })
    console.log("  deactivated active same-code", p.id)
  }

  const created = await stripe.promotionCodes.create({
    promotion: {
      type: "coupon",
      coupon: coupon.id,
    },
    code,
    active: true,
    metadata: {
      affiliate_user_id: row.user_id,
      affiliate_code: code,
      tradetraxs_purpose: PURPOSE,
    },
  })

  const { error: upErr } = await supabase
    .from("affiliates")
    .update({ stripe_promo_code_id: created.id })
    .eq("user_id", row.user_id)

  if (upErr) {
    console.error("  DB update failed:", upErr)
  } else {
    console.log("  created", created.id, "and updated affiliates row")
  }
}

console.log(`
Done.
IMPORTANT: Existing customers who already have a forever discount on their
active Stripe subscription are NOT modified by this script. They keep that
discount until the subscription ends or is manually changed in Stripe.
New checkouts for these affiliate codes will use the once/10% coupon.
`)
