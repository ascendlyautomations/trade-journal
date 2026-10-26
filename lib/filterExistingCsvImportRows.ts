import type { SupabaseClient } from "@supabase/supabase-js"

/** Drop CSV rows whose fingerprint already exists for this user (and optional account). */
export async function filterExistingCsvImportRows<
  T extends { import_fingerprint?: string | null },
>(
  client: SupabaseClient,
  userId: string,
  rows: T[],
  accountId?: string | null
): Promise<T[]> {
  const fingerprints = rows
    .map((row) => String(row.import_fingerprint ?? "").trim())
    .filter(Boolean)
  if (fingerprints.length === 0) return rows

  let query = client
    .from("trades")
    .select("import_fingerprint")
    .eq("user_id", userId)
    .eq("import_source", "csv")
    .in("import_fingerprint", fingerprints)

  if (accountId) {
    query = query.eq("account_id", accountId)
  } else {
    query = query.is("account_id", null)
  }

  const { data: existingRows } = await query
  const existing = new Set(
    (existingRows ?? []).map((row) => String(row.import_fingerprint ?? ""))
  )
  return rows.filter((row) => !existing.has(String(row.import_fingerprint ?? "")))
}
