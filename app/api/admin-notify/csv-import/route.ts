import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { SITE_URL } from "@/lib/site"
import { sendCsvImportAdminEmail } from "@/lib/server/sendCsvImportAdminEmail"

type CsvImportNotifyBody = {
  importBatchId?: string
  originalFilename?: string | null
  brokerFormat?: string | null
  rowsParsed?: number
  tradesImported?: number
  rowsSkipped?: number | null
  accountName?: string | null
  accountId?: string | null
  source?: string | null
}

function asNonNegativeInt(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null
  const n = Math.floor(value)
  return n >= 0 ? n : null
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: CsvImportNotifyBody
  try {
    body = (await req.json()) as CsvImportNotifyBody
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const importBatchId = body.importBatchId?.trim()
  if (!importBatchId) {
    return Response.json({ error: "importBatchId is required" }, { status: 400 })
  }

  const tradesImported = asNonNegativeInt(body.tradesImported)
  if (tradesImported == null || tradesImported < 1) {
    return Response.json({ error: "tradesImported must be at least 1" }, { status: 400 })
  }

  const rowsParsed = asNonNegativeInt(body.rowsParsed) ?? tradesImported
  const rowsSkippedRaw = asNonNegativeInt(body.rowsSkipped)

  const { data: profile } = await supabaseServiceRole
    .from("profiles")
    .select("username, name")
    .eq("id", user.id)
    .maybeSingle()

  const emailResult = await sendCsvImportAdminEmail({
    userId: user.id,
    userEmail: user.email ?? null,
    username: profile?.username != null ? String(profile.username) : null,
    displayName: profile?.name != null ? String(profile.name) : null,
    originalFilename:
      body.originalFilename != null ? String(body.originalFilename).trim() || null : null,
    brokerFormat:
      body.brokerFormat != null ? String(body.brokerFormat).trim() || null : null,
    rowsParsed,
    tradesImported,
    rowsSkipped: rowsSkippedRaw,
    accountName:
      body.accountName != null ? String(body.accountName).trim() || null : null,
    accountId: body.accountId != null ? String(body.accountId).trim() || null : null,
    source: body.source != null ? String(body.source).trim() || null : null,
    createdAt: new Date().toISOString(),
    adminUrl: `${SITE_URL}/admin/users`,
  })

  if (!emailResult.ok && !emailResult.skipped) {
    console.error("[admin-notify/csv-import] email failed", {
      userId: user.id,
      importBatchId,
      error: emailResult.error,
    })
  }

  return Response.json({ ok: true, emailSent: emailResult.ok })
}
