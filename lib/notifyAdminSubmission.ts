import { supabase } from "@/lib/supabaseClient"
import type { AdminSubmissionType } from "@/lib/adminSubmissionTypes"

/** Fire-and-forget admin email after a successful user submission (never throws). */
export function notifyAdminSubmission(
  type: AdminSubmissionType,
  recordId: string
): void {
  void (async () => {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) {
        console.warn("[admin-notify] skipped: no session")
        return
      }

      const res = await fetch("/api/admin-notify/submission", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ type, recordId }),
      })

      if (!res.ok) {
        const text = await res.text()
        console.error("[admin-notify] API failed", {
          type,
          recordId,
          status: res.status,
          body: text,
        })
      }
    } catch (err) {
      console.error("[admin-notify] request failed", { type, recordId, err })
    }
  })()
}
