import { supabase } from "@/lib/supabaseClient"

export type NotifyAdminCsvImportPayload = {
  /** Client-generated idempotency key for this successful import batch. */
  importBatchId: string
  originalFilename?: string | null
  brokerFormat?: string | null
  rowsParsed: number
  tradesImported: number
  rowsSkipped?: number
  accountName?: string | null
  accountId?: string | null
  source?: string | null
}

/** In-memory guard: one admin email per import batch (React Strict Mode / double callbacks). */
const notifiedImportBatchIds = new Set<string>()

/** Fire-and-forget admin email after a successful CSV trade insert (never throws). */
export function notifyAdminCsvImportCompleted(
  payload: NotifyAdminCsvImportPayload
): void {
  const batchId = payload.importBatchId?.trim()
  if (!batchId) return
  if (notifiedImportBatchIds.has(batchId)) return
  if (!Number.isFinite(payload.tradesImported) || payload.tradesImported < 1) return

  notifiedImportBatchIds.add(batchId)

  void (async () => {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) {
        console.warn("[admin-notify/csv-import] skipped: no session")
        return
      }

      const res = await fetch("/api/admin-notify/csv-import", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          importBatchId: batchId,
          originalFilename: payload.originalFilename ?? null,
          brokerFormat: payload.brokerFormat ?? null,
          rowsParsed: payload.rowsParsed,
          tradesImported: payload.tradesImported,
          rowsSkipped: payload.rowsSkipped ?? null,
          accountName: payload.accountName ?? null,
          accountId: payload.accountId ?? null,
          source: payload.source ?? null,
        }),
      })

      if (!res.ok) {
        const text = await res.text()
        console.error("[admin-notify/csv-import] API failed", {
          importBatchId: batchId,
          status: res.status,
          body: text,
        })
      }
    } catch (err) {
      console.error("[admin-notify/csv-import] request failed", {
        importBatchId: batchId,
        err,
      })
    }
  })()
}
