import { supabase } from "@/lib/supabaseClient"

/** Fire-and-forget in-app affiliate referral alert after attribution (never throws). */
export function notifyAffiliateReferralAttribution(): void {
  void (async () => {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) {
        console.warn("[affiliate-referral-notify] skipped: no session")
        return
      }

      const res = await fetch("/api/notifications/affiliate-referral", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      })

      if (!res.ok) {
        const text = await res.text()
        console.error("[affiliate-referral-notify] API failed", {
          status: res.status,
          body: text,
        })
      }
    } catch (err) {
      console.error("[affiliate-referral-notify] request failed", err)
    }
  })()
}
