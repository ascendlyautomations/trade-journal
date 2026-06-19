import type { SupabaseClient } from "@supabase/supabase-js"

export type SubmitCsvSupportInput = {
  userId: string
  csvFile: File
  brokerName: string
  notes?: string | null
}

export function sanitizeCsvSupportFilename(name: string): string {
  return name.replace(/[^\w.\-]+/g, "_").slice(0, 120) || "sample.csv"
}

export async function submitCsvSupportRequest(
  supabase: SupabaseClient,
  input: SubmitCsvSupportInput
): Promise<{ ok: true; filePath: string } | { ok: false; message: string }> {
  const broker = input.brokerName.trim() || "Unknown"
  const safeName = sanitizeCsvSupportFilename(input.csvFile.name)
  const filePath = `${input.userId}/${Date.now()}-${safeName}`

  const { error: uploadError } = await supabase.storage
    .from("csv-support")
    .upload(filePath, input.csvFile, {
      upsert: false,
      contentType: input.csvFile.type || "text/csv",
    })

  if (uploadError) {
    return { ok: false, message: uploadError.message }
  }

  const { error: insertError } = await supabase.from("csv_support_requests").insert({
    user_id: input.userId,
    broker_name: broker,
    notes: input.notes?.trim() || null,
    csv_file_url: filePath,
    status: "new",
  })

  if (insertError) {
    return { ok: false, message: insertError.message }
  }

  return { ok: true, filePath }
}
