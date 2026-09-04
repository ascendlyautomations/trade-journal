import { NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  CONTENT_REPORT_REASONS,
  CONTENT_REPORT_TARGET_TYPES,
  isContentReportReason,
  isContentReportTargetType,
  type ContentReportReason,
  type ContentReportTargetType,
} from "@/lib/contentReports"

type CreateContentReportBody = {
  targetType?: string
  targetId?: string
  reportedUserId?: string | null
  reason?: string
  details?: string | null
}

const MAX_DETAILS_LENGTH = 2000

function normalizeDetails(value: unknown): string | null {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  if (!trimmed) return null
  return trimmed.slice(0, MAX_DETAILS_LENGTH)
}

/**
 * Authenticated users submit in-app UGC reports.
 * Reporter identity is always derived from the session — never from the body.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: CreateContentReportBody
  try {
    body = (await req.json()) as CreateContentReportBody
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const targetTypeRaw = body.targetType?.trim().toLowerCase() ?? ""
  const targetId = body.targetId?.trim() ?? ""
  const reasonRaw = body.reason?.trim().toLowerCase() ?? ""
  const details = normalizeDetails(body.details)
  const reportedUserId =
    typeof body.reportedUserId === "string" && body.reportedUserId.trim()
      ? body.reportedUserId.trim()
      : null

  if (!isContentReportTargetType(targetTypeRaw)) {
    return NextResponse.json({ error: "Invalid targetType" }, { status: 400 })
  }
  const targetType: ContentReportTargetType = targetTypeRaw

  if (!targetId || targetId.length > 256) {
    return NextResponse.json({ error: "Invalid targetId" }, { status: 400 })
  }

  if (!isContentReportReason(reasonRaw)) {
    return NextResponse.json({ error: "Invalid reason" }, { status: 400 })
  }
  const reason: ContentReportReason = reasonRaw

  if (targetType === "user" && targetId === user.id) {
    return NextResponse.json({ error: "Cannot report yourself" }, { status: 400 })
  }

  if (reportedUserId && reportedUserId === user.id) {
    return NextResponse.json(
      { error: "Cannot report your own content" },
      { status: 400 }
    )
  }

  const db = supabaseServiceRole

  const { data, error } = await db
    .from("content_reports")
    .insert({
      reporter_user_id: user.id,
      target_type: targetType,
      target_id: targetId,
      reported_user_id: reportedUserId,
      reason,
      details,
      status: "open",
    })
    .select("id, status, created_at")
    .single()

  if (error) {
    if (error.code === "23505") {
      return NextResponse.json({
        ok: true,
        duplicate: true,
        message: "You already reported this content.",
      })
    }
    console.error("[api/content-reports] insert failed", error.message)
    return NextResponse.json({ error: "Report submission failed" }, { status: 500 })
  }

  return NextResponse.json({
    ok: true,
    id: data.id,
    status: data.status,
    createdAt: data.created_at,
  })
}

/** Safe export for OpenAPI / client discovery — no secrets. */
export function GET() {
  return NextResponse.json({
    targetTypes: CONTENT_REPORT_TARGET_TYPES,
    reasons: CONTENT_REPORT_REASONS,
  })
}
