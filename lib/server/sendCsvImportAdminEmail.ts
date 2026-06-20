import { LEGAL_CONTACT_EMAIL } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const CSV_IMPORT_ADMIN_EMAIL_SUBJECT = "[TradeTraxs] CSV Import Completed"

export type CsvImportAdminEmailContext = {
  userId: string
  userEmail: string | null
  username: string | null
  displayName: string | null
  originalFilename: string | null
  brokerFormat: string | null
  rowsParsed: number
  tradesImported: number
  rowsSkipped: number | null
  accountName: string | null
  accountId: string | null
  source: string | null
  createdAt: string
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

export function buildCsvImportAdminEmailHtml(ctx: CsvImportAdminEmailContext): string {
  const rows = [
    row("User ID", ctx.userId),
    row("Username", ctx.username),
    row("Display name", ctx.displayName),
    row("User email", ctx.userEmail),
    row("Original CSV filename", ctx.originalFilename),
    row("Detected broker / format", ctx.brokerFormat),
    row("Rows parsed", String(ctx.rowsParsed)),
    row("Trades imported", String(ctx.tradesImported)),
    row(
      "Rows skipped",
      ctx.rowsSkipped != null && ctx.rowsSkipped > 0
        ? String(ctx.rowsSkipped)
        : "0"
    ),
    row("Account name", ctx.accountName),
    row("Account ID", ctx.accountId),
    row("Import source", ctx.source),
    row("Created", new Date(ctx.createdAt).toLocaleString("en-US")),
    rowHtml(
      "Admin",
      `<a href="${escapeHtml(ctx.adminUrl)}" style="color:#38bdf8">${escapeHtml(ctx.adminUrl)}</a>`
    ),
  ]

  return `<!DOCTYPE html><html><body style="margin:0;padding:24px;background:#0f172a;font-family:system-ui,sans-serif">
<div style="max-width:640px;margin:0 auto;background:#1e293b;border:1px solid #334155;border-radius:12px;padding:24px">
<h1 style="margin:0 0 16px;font-size:18px;color:#f8fafc">${escapeHtml(CSV_IMPORT_ADMIN_EMAIL_SUBJECT)}</h1>
<table style="width:100%;border-collapse:collapse;font-size:14px">${rows.join("")}</table>
<p style="margin:24px 0 0;font-size:12px;color:#64748b">TradeTraxs admin notification · ${escapeHtml(SITE_URL)}</p>
</div></body></html>`
}

export async function sendCsvImportAdminEmail(
  ctx: CsvImportAdminEmailContext
): Promise<{ ok: true } | { ok: false; skipped?: boolean; error?: string }> {
  const apiKey = process.env.RESEND_API_KEY?.trim()
  if (!apiKey) {
    console.warn("[admin-email/csv-import] RESEND_API_KEY not set; skipping notification email")
    return { ok: false, skipped: true }
  }

  const from =
    process.env.ADMIN_NOTIFY_FROM_EMAIL?.trim() ||
    "TradeTraxs Notifications <notifications@tradetraxs.com>"

  const html = buildCsvImportAdminEmailHtml(ctx)

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
        subject: CSV_IMPORT_ADMIN_EMAIL_SUBJECT,
        html,
      }),
    })

    if (!res.ok) {
      const text = await res.text()
      console.error("[admin-email/csv-import] Resend API error", {
        userId: ctx.userId,
        status: res.status,
        body: text,
      })
      return { ok: false, error: text }
    }

    return { ok: true }
  } catch (err) {
    console.error("[admin-email/csv-import] send failed", { userId: ctx.userId, err })
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Unknown email error",
    }
  }
}
