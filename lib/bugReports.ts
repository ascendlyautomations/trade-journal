import { supabase } from "@/lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import {
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

export type BugReportSeverity = "low" | "medium" | "high" | "critical"
export type BugReportStatus = "open" | "in_progress" | "resolved"

export const BUG_REPORT_SEVERITY_OPTIONS: {
  value: BugReportSeverity
  label: string
}[] = [
  { value: "low", label: "Low, cosmetic or minor" },
  { value: "medium", label: "Medium, affects workflow" },
  { value: "high", label: "High, major feature broken" },
  { value: "critical", label: "Critical, blocker" },
]

export const BUG_REPORT_STATUS_OPTIONS: {
  value: BugReportStatus
  label: string
}[] = [
  { value: "open", label: "Open" },
  { value: "in_progress", label: "In progress" },
  { value: "resolved", label: "Resolved" },
]

export type BugReportRow = {
  id: string
  user_id: string
  title: string
  description: string
  screenshot_url: string | null
  page_url: string | null
  browser_info: string | null
  severity: BugReportSeverity
  status: BugReportStatus
  created_at: string
  resolved_at: string | null
}

export function capturePageUrl(): string {
  if (typeof window === "undefined") return ""
  return `${window.location.pathname}${window.location.search}${window.location.hash}`
}

export function captureBrowserInfo(): string {
  if (typeof navigator === "undefined") return ""
  const parts = [
    navigator.userAgent,
    `lang=${navigator.language}`,
    typeof window !== "undefined" ? `${window.innerWidth}x${window.innerHeight}` : "",
  ].filter(Boolean)
  return parts.join(" · ")
}

export type SubmitBugReportInput = {
  title: string
  description: string
  severity: BugReportSeverity
  screenshotFile?: File | null
  pageUrl?: string
  browserInfo?: string
}

export async function submitBugReport(
  userId: string,
  input: SubmitBugReportInput
): Promise<{ ok: true } | { ok: false; message: string }> {
  const title = input.title.trim()
  const description = input.description.trim()
  if (!title || !description) {
    return { ok: false, message: "Title and description are required." }
  }

  let screenshotUrl: string | null = null
  const file = input.screenshotFile
  if (file) {
    let uploadFile: File = file
    if (file.type?.startsWith("image/")) {
      uploadFile = await compressImage(file)
    }
    const safeName = uploadFile.name.replace(/[^\w.\-()+]/g, "_")
    const filePath = `bug-reports/${userId}/${Date.now()}-${safeName}`
    const { error: uploadError } = await supabase.storage
      .from("screenshots")
      .upload(filePath, uploadFile, { upsert: false })

    if (uploadError) {
      console.error("[bugReports] upload failed", uploadError)
      return {
        ok: false,
        message: toUserFacingErrorMessage(
          uploadError,
          USER_FACING_ERROR_MESSAGES.FILE_UPLOAD_FAILED
        ),
      }
    }

    const { data: publicData } = supabase.storage
      .from("screenshots")
      .getPublicUrl(filePath)
    screenshotUrl = publicData.publicUrl
  }

  const { data, error: insertError } = await supabase
    .from("bug_reports")
    .insert({
      user_id: userId,
      title,
      description,
      severity: input.severity,
      screenshot_url: screenshotUrl,
      page_url: input.pageUrl?.trim() || null,
      browser_info: input.browserInfo?.trim() || null,
    })
    .select("id")
    .single()

  if (insertError) {
    console.error("[bugReports] insert failed", insertError)
    return {
      ok: false,
      message: toUserFacingErrorMessage(insertError),
    }
  }

  if (data?.id) {
    notifyAdminSubmission("bug_report", data.id)
  }

  return { ok: true }
}
