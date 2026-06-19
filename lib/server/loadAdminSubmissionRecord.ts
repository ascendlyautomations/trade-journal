import {
  ADMIN_SUBMISSION_ADMIN_PATHS,
  ADMIN_SUBMISSION_LABELS,
  type AdminSubmissionType,
} from "@/lib/adminSubmissionTypes"
import { SITE_URL } from "@/lib/site"
import type { AdminSubmissionEmailContext } from "@/lib/server/sendAdminSubmissionEmail"
import type { SupabaseClient } from "@supabase/supabase-js"

type LoadResult =
  | { ok: true; context: AdminSubmissionEmailContext }
  | { ok: false; status: number; error: string }

function adminUrl(type: AdminSubmissionType): string {
  return `${SITE_URL}${ADMIN_SUBMISSION_ADMIN_PATHS[type]}`
}

export async function loadAdminSubmissionEmailContext(
  admin: SupabaseClient,
  type: AdminSubmissionType,
  recordId: string,
  userId: string,
  userEmail: string | null
): Promise<LoadResult> {
  const { data: profile } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", userId)
    .maybeSingle()

  const base = {
    type,
    recordId,
    userId,
    userEmail,
    username: profile?.username ?? null,
    displayName: profile?.name ?? null,
    adminUrl: adminUrl(type),
  }

  if (type === "bug_report") {
    const { data, error } = await admin
      .from("bug_reports")
      .select(
        "id, user_id, title, description, severity, page_url, browser_info, screenshot_url, created_at"
      )
      .eq("id", recordId)
      .maybeSingle()

    if (error || !data || data.user_id !== userId) {
      return { ok: false, status: 404, error: "Bug report not found" }
    }

    return {
      ok: true,
      context: {
        ...base,
        createdAt: data.created_at,
        title: data.title,
        description: data.description,
        severity: data.severity,
        extraFields: [
          { label: "Page URL", value: data.page_url },
          { label: "Browser", value: data.browser_info },
          { label: "Screenshot", value: data.screenshot_url },
        ],
      },
    }
  }

  if (type === "feature_request") {
    const { data, error } = await admin
      .from("feature_requests")
      .select("id, user_id, title, description, created_at")
      .eq("id", recordId)
      .maybeSingle()

    if (error || !data || data.user_id !== userId) {
      return { ok: false, status: 404, error: "Feature request not found" }
    }

    return {
      ok: true,
      context: {
        ...base,
        createdAt: data.created_at,
        title: data.title,
        description: data.description,
      },
    }
  }

  if (type === "support_ticket") {
    const { data, error } = await admin
      .from("support_tickets")
      .select(
        "id, user_id, email, category, subject, message, screenshot_url, status, created_at"
      )
      .eq("id", recordId)
      .maybeSingle()

    if (error || !data || data.user_id !== userId) {
      return { ok: false, status: 404, error: "Support ticket not found" }
    }

    return {
      ok: true,
      context: {
        ...base,
        createdAt: data.created_at,
        title: data.subject,
        description: data.message,
        category: data.category,
        userEmail: data.email ?? userEmail,
        extraFields: [
          { label: "Status", value: data.status },
          { label: "Screenshot", value: data.screenshot_url },
        ],
      },
    }
  }

  if (type === "csv_support_request") {
    const { data, error } = await admin
      .from("csv_support_requests")
      .select("id, user_id, broker_name, notes, csv_file_url, status, created_at")
      .eq("id", recordId)
      .maybeSingle()

    if (error || !data || data.user_id !== userId) {
      return { ok: false, status: 404, error: "CSV support request not found" }
    }

    return {
      ok: true,
      context: {
        ...base,
        createdAt: data.created_at,
        brokerName: data.broker_name,
        notes: data.notes,
        title: ADMIN_SUBMISSION_LABELS.csv_support_request,
        extraFields: [
          { label: "Status", value: data.status },
          { label: "CSV file path", value: data.csv_file_url },
        ],
      },
    }
  }

  if (type === "feedback_submission") {
    const { data, error } = await admin
      .from("feedback_submissions")
      .select(
        "id, user_id, email, subject, message, screenshot_url, status, created_at"
      )
      .eq("id", recordId)
      .maybeSingle()

    if (error || !data || data.user_id !== userId) {
      return { ok: false, status: 404, error: "Feedback submission not found" }
    }

    return {
      ok: true,
      context: {
        ...base,
        createdAt: data.created_at,
        title: data.subject || "Feedback",
        description: data.message,
        userEmail: data.email ?? userEmail,
        extraFields: [
          { label: "Status", value: data.status },
          { label: "Screenshot", value: data.screenshot_url },
        ],
      },
    }
  }

  return { ok: false, status: 400, error: "Unknown submission type" }
}
