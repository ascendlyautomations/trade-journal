import type { SupabaseClient } from "@supabase/supabase-js"

/** DB status values (csv_support_requests_status_ck). */
export const CSV_SUPPORT_STATUS_OPTIONS = [
  { value: "new", label: "New" },
  { value: "in_progress", label: "Reviewing" },
  { value: "resolved", label: "Supported" },
  { value: "closed", label: "Rejected" },
] as const

export type CsvSupportRequestStatus = (typeof CSV_SUPPORT_STATUS_OPTIONS)[number]["value"]

export type CsvSupportRequestRow = {
  id: string
  user_id: string | null
  broker_name: string | null
  notes: string | null
  csv_file_url: string | null
  created_at: string
  status: CsvSupportRequestStatus | string
}

export type CsvSupportProfileHint = {
  id: string
  username: string | null
  name: string | null
  is_beta_tester: boolean | null
}

export function csvSupportStatusLabel(status: string | null | undefined): string {
  const match = CSV_SUPPORT_STATUS_OPTIONS.find((o) => o.value === status)
  return match?.label ?? status ?? "—"
}

export function csvStorageFilename(path: string | null | undefined): string {
  if (!path?.trim()) return "—"
  const parts = path.split("/")
  return parts[parts.length - 1] || path
}

export async function createCsvSupportSignedDownloadUrl(
  supabase: SupabaseClient,
  storagePath: string
): Promise<{ url: string } | { error: string }> {
  const trimmed = storagePath.trim()
  if (!trimmed) {
    return { error: "Missing storage path" }
  }

  const { data, error } = await supabase.storage
    .from("csv-support")
    .createSignedUrl(trimmed, 3600)

  if (error || !data?.signedUrl) {
    return { error: error?.message || "Could not create download link" }
  }

  return { url: data.signedUrl }
}

export function formatCsvSupportUserLabel(
  userId: string | null | undefined,
  profile?: CsvSupportProfileHint | null
): string {
  if (profile?.username?.trim()) {
    return `@${profile.username.trim()}`
  }
  if (profile?.name?.trim()) {
    return profile.name.trim()
  }
  if (userId) return userId
  return "Unknown user"
}
