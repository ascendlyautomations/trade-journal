import type { SupabaseClient } from "@supabase/supabase-js"

export type SubmitCsvSupportInput = {
  csvFile: File
  brokerName: string
  notes?: string | null
}

/** Matches /csv-support page + csv_support_requests_insert_own RLS (user_id = auth.uid()). */
export type CsvSupportRequestInsertPayload = {
  user_id: string
  broker_name: string
  notes: string | null
  csv_file_url: string
  status: "new"
}

export function sanitizeCsvSupportFilename(name: string): string {
  return name.replace(/[^\w.\-]+/g, "_").slice(0, 120) || "sample.csv"
}

export function buildCsvSupportRequestInsertPayload(
  userId: string,
  filePath: string,
  brokerName: string,
  notes?: string | null
): CsvSupportRequestInsertPayload {
  return {
    user_id: userId,
    broker_name: brokerName.trim() || "Unknown",
    notes: notes?.trim() || null,
    csv_file_url: filePath,
    status: "new",
  }
}

export async function submitCsvSupportRequest(
  supabase: SupabaseClient,
  input: SubmitCsvSupportInput
): Promise<{ ok: true; filePath: string } | { ok: false; message: string }> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user?.id) {
    return { ok: false, message: "You must be logged in to submit a CSV." }
  }

  const { data: sessionData } = await supabase.auth.getSession()
  if (!sessionData.session?.access_token) {
    const { data: refreshed, error: refreshError } =
      await supabase.auth.refreshSession()
    if (refreshError || !refreshed.session?.access_token) {
      return { ok: false, message: "You must be logged in to submit a CSV." }
    }
  }

  const userId = user.id
  const safeName = sanitizeCsvSupportFilename(input.csvFile.name)
  const filePath = `${userId}/${Date.now()}-${safeName}`
  const insertPayload = buildCsvSupportRequestInsertPayload(
    userId,
    filePath,
    input.brokerName,
    input.notes
  )

  if (process.env.NODE_ENV === "development") {
    console.debug("[csv-support] submit", {
      userId,
      filePath,
      insertPayloadKeys: Object.keys(insertPayload),
    })
  }

  const { error: uploadError } = await supabase.storage
    .from("csv-support")
    .upload(filePath, input.csvFile, {
      upsert: false,
      contentType: input.csvFile.type || "text/csv",
    })

  if (uploadError) {
    return { ok: false, message: uploadError.message }
  }

  const { error: insertError } = await supabase
    .from("csv_support_requests")
    .insert(insertPayload)

  if (insertError) {
    return { ok: false, message: insertError.message }
  }

  return { ok: true, filePath }
}
