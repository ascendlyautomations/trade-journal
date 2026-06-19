import { LEGAL_CONTACT_EMAIL } from "@/lib/legal/contact"
import {
  ADMIN_SUBMISSION_EMAIL_SUBJECTS,
  type AdminSubmissionType,
} from "@/lib/adminSubmissionTypes"
import { SITE_URL } from "@/lib/site"

export type AdminSubmissionEmailContext = {
  type: AdminSubmissionType
  recordId: string
  userId: string
  userEmail: string | null
  username: string | null
  displayName: string | null
  createdAt: string | null
  title?: string | null
  description?: string | null
  notes?: string | null
  brokerName?: string | null
  category?: string | null
  severity?: string | null
  adminUrl: string
  extraFields?: { label: string; value: string | null | undefined }[]
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

export function buildAdminSubmissionEmailHtml(ctx: AdminSubmissionEmailContext): string {
  const rows = [
    row("Request type", ctx.type.replace(/_/g, " ")),
    row("Record ID", ctx.recordId),
    row("User ID", ctx.userId),
    row("Username", ctx.username),
    row("Display name", ctx.displayName),
    row("User email", ctx.userEmail),
    row("Created", ctx.createdAt ? new Date(ctx.createdAt).toLocaleString("en-US") : null),
    ctx.title != null ? row("Title", ctx.title) : "",
    ctx.category != null ? row("Category", ctx.category) : "",
    ctx.severity != null ? row("Severity", ctx.severity) : "",
    ctx.brokerName != null ? row("Broker / platform", ctx.brokerName) : "",
    ctx.description != null ? row("Description", ctx.description) : "",
    ctx.notes != null ? row("Notes", ctx.notes) : "",
    ...(ctx.extraFields ?? []).map((f) => row(f.label, f.value ?? null)),
    rowHtml(
      "Admin",
      `<a href="${escapeHtml(ctx.adminUrl)}" style="color:#38bdf8">${escapeHtml(ctx.adminUrl)}</a>`
    ),
  ].filter(Boolean)

  return `<!DOCTYPE html><html><body style="margin:0;padding:24px;background:#0f172a;font-family:system-ui,sans-serif">
<div style="max-width:640px;margin:0 auto;background:#1e293b;border:1px solid #334155;border-radius:12px;padding:24px">
<h1 style="margin:0 0 16px;font-size:18px;color:#f8fafc">${escapeHtml(ADMIN_SUBMISSION_EMAIL_SUBJECTS[ctx.type])}</h1>
<table style="width:100%;border-collapse:collapse;font-size:14px">${rows.join("")}</table>
<p style="margin:24px 0 0;font-size:12px;color:#64748b">TradeTraxs admin notification · ${escapeHtml(SITE_URL)}</p>
</div></body></html>`
}

export async function sendAdminSubmissionEmail(
  ctx: AdminSubmissionEmailContext
): Promise<{ ok: true } | { ok: false; skipped?: boolean; error?: string }> {
  const apiKey = process.env.RESEND_API_KEY?.trim()
  if (!apiKey) {
    console.warn("[admin-email] RESEND_API_KEY not set; skipping notification email")
    return { ok: false, skipped: true }
  }

  const from =
    process.env.ADMIN_NOTIFY_FROM_EMAIL?.trim() ||
    "TradeTraxs Notifications <notifications@tradetraxs.com>"

  const subject = ADMIN_SUBMISSION_EMAIL_SUBJECTS[ctx.type]
  const html = buildAdminSubmissionEmailHtml(ctx)

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
        subject,
        html,
      }),
    })

    if (!res.ok) {
      const text = await res.text()
      console.error("[admin-email] Resend API error", {
        type: ctx.type,
        recordId: ctx.recordId,
        status: res.status,
        body: text,
      })
      return { ok: false, error: text }
    }

    return { ok: true }
  } catch (err) {
    console.error("[admin-email] send failed", {
      type: ctx.type,
      recordId: ctx.recordId,
      err,
    })
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Unknown email error",
    }
  }
}
