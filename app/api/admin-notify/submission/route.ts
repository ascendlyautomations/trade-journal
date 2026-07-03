import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import type { AdminSubmissionType } from "@/lib/adminSubmissionTypes"
import { loadAdminSubmissionEmailContext } from "@/lib/server/loadAdminSubmissionRecord"
import { sendAdminSubmissionEmail } from "@/lib/server/sendAdminSubmissionEmail"

const VALID_TYPES = new Set<AdminSubmissionType>([
  "bug_report",
  "feature_request",
  "support_ticket",
  "csv_support_request",
  "feedback_submission",
  "affiliate_application",
  "user_review",
])

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: { type?: string; recordId?: string }
  try {
    body = (await req.json()) as { type?: string; recordId?: string }
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const type = body.type as AdminSubmissionType | undefined
  const recordId = body.recordId?.trim()

  if (!type || !VALID_TYPES.has(type) || !recordId) {
    return Response.json({ error: "Invalid type or recordId" }, { status: 400 })
  }

  const loaded = await loadAdminSubmissionEmailContext(
    supabaseServiceRole,
    type,
    recordId,
    user.id,
    user.email ?? null
  )

  if (!loaded.ok) {
    return Response.json({ error: loaded.error }, { status: loaded.status })
  }

  const emailResult = await sendAdminSubmissionEmail(loaded.context)
  if (!emailResult.ok && !emailResult.skipped) {
    console.error("[admin-notify/submission] email failed", {
      type,
      recordId,
      error: emailResult.error,
    })
  }

  return Response.json({ ok: true, emailSent: emailResult.ok })
}
