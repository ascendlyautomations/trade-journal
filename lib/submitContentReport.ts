import type {
  ContentReportReason,
  ContentReportTargetType,
} from "@/lib/contentReports"

export type SubmitContentReportInput = {
  targetType: ContentReportTargetType
  targetId: string
  reportedUserId?: string | null
  reason: ContentReportReason
  details?: string | null
}

export type SubmitContentReportResult =
  | { ok: true; duplicate?: boolean }
  | { ok: false; message: string }

export async function submitContentReport(
  input: SubmitContentReportInput
): Promise<SubmitContentReportResult> {
  const res = await fetch("/api/content-reports", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      targetType: input.targetType,
      targetId: input.targetId,
      reportedUserId: input.reportedUserId ?? null,
      reason: input.reason,
      details: input.details ?? null,
    }),
  })
  let body: { error?: string; duplicate?: boolean; ok?: boolean } = {}
  try {
    body = (await res.json()) as typeof body
  } catch {
    body = {}
  }
  if (!res.ok) {
    return {
      ok: false,
      message: body.error ?? "Report submission failed.",
    }
  }
  return { ok: true, duplicate: body.duplicate === true }
}
