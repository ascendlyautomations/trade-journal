import { BETA_REFERRAL_CODE } from "@/lib/betaReferralCode"
import { LEGAL_CONTACT_EMAIL } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const BETA_SIGNUP_ADMIN_EMAIL_SUBJECT = "[TradeTraxs] New Beta User Signup"

export type BetaSignupEmailContext = {
  userId: string
  userEmail: string | null
  username: string | null
  name: string | null
  displayName: string | null
  referredBy: string | null
  isBetaTester: boolean
  isPro: boolean
  createdAt: string | null
  profileCompletedAt: string | null
  signupMethod: string | null
  adminUrl: string
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function row(label: string, value: string | null | undefined): string {
  const safe = escapeHtml(value?.trim() || "—")
  return `<tr><td style="padding:6px 12px 6px 0;color:#64748b;vertical-align:top;white-space:nowrap">${escapeHtml(label)}</td><td style="padding:6px 0;color:#e2e8f0">${safe}</td></tr>`
}

function rowHtml(label: string, html: string): string {
  return `<tr><td style="padding:6px 12px 6px 0;color:#64748b;vertical-align:top;white-space:nowrap">${escapeHtml(label)}</td><td style="padding:6px 0;color:#e2e8f0">${html}</td></tr>`
}

export function buildBetaSignupAdminEmailHtml(ctx: BetaSignupEmailContext): string {
  const rows = [
    row("User ID", ctx.userId),
    row("User email", ctx.userEmail),
    row("Username", ctx.username),
    row("Name", ctx.name ?? ctx.displayName),
    row("Display name", ctx.displayName),
    row("Referred by", ctx.referredBy ?? BETA_REFERRAL_CODE),
    row("Beta tester", ctx.isBetaTester ? "Yes" : "No"),
    row("Pro access", ctx.isPro ? "Yes" : "No"),
    row("Account created", ctx.createdAt ? new Date(ctx.createdAt).toLocaleString("en-US") : null),
    row(
      "Profile completed",
      ctx.profileCompletedAt
        ? new Date(ctx.profileCompletedAt).toLocaleString("en-US")
        : null
    ),
    row("Signup method", ctx.signupMethod),
    rowHtml(
      "Admin",
      `<a href="${escapeHtml(ctx.adminUrl)}" style="color:#38bdf8">${escapeHtml(ctx.adminUrl)}</a>`
    ),
  ]

  return `<!DOCTYPE html><html><body style="margin:0;padding:24px;background:#0f172a;font-family:system-ui,sans-serif">
<div style="max-width:640px;margin:0 auto;background:#1e293b;border:1px solid #334155;border-radius:12px;padding:24px">
<h1 style="margin:0 0 16px;font-size:18px;color:#f8fafc">${escapeHtml(BETA_SIGNUP_ADMIN_EMAIL_SUBJECT)}</h1>
<table style="width:100%;border-collapse:collapse;font-size:14px">${rows.join("")}</table>
<p style="margin:24px 0 0;font-size:12px;color:#64748b">TradeTraxs admin notification · ${escapeHtml(SITE_URL)}</p>
</div></body></html>`
}

export async function sendBetaSignupAdminEmail(
  ctx: BetaSignupEmailContext
): Promise<
  | { ok: true; emailId: string | null }
  | { ok: false; skipped?: boolean; error?: string }
> {
  const apiKey = process.env.RESEND_API_KEY?.trim()
  if (!apiKey) {
    console.warn("[admin-email/beta-signup] RESEND_API_KEY not set; skipping notification email")
    return { ok: false, skipped: true }
  }

  const from =
    process.env.ADMIN_NOTIFY_FROM_EMAIL?.trim() ||
    "TradeTraxs Notifications <notifications@tradetraxs.com>"

  const html = buildBetaSignupAdminEmailHtml(ctx)

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [LEGAL_CONTACT_EMAIL],
        subject: BETA_SIGNUP_ADMIN_EMAIL_SUBJECT,
        html,
      }),
    })

    if (!res.ok) {
      const text = await res.text()
      console.error("[beta-signup-email] resend error", {
        userId: ctx.userId,
        status: res.status,
        body: text,
      })
      return { ok: false, error: text }
    }

    let emailId: string | null = null
    try {
      const payload = (await res.json()) as { id?: string }
      emailId = payload.id?.trim() || null
    } catch {
      emailId = null
    }

    return { ok: true, emailId }
  } catch (err) {
    console.error("[admin-email/beta-signup] send failed", { userId: ctx.userId, err })
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Unknown email error",
    }
  }
}
