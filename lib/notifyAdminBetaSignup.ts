import { supabase } from "@/lib/supabaseClient"

const SESSION_GUARD_PREFIX = "beta-signup-notify:"

/** Fire-and-forget admin email when a user becomes a beta tester (never throws). */
export function notifyAdminBetaSignup(signupMethod?: string): void {
  void (async () => {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const token = session?.access_token
      const userId = session?.user?.id
      if (!token || !userId) {
        console.warn("[admin-notify/beta-signup] skipped: no session")
        return
      }

      if (typeof window !== "undefined") {
        const guardKey = `${SESSION_GUARD_PREFIX}${userId}`
        if (sessionStorage.getItem(guardKey)) return
        sessionStorage.setItem(guardKey, "1")
      }

      const res = await fetch("/api/admin-notify/beta-signup", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          signupMethod: signupMethod?.trim() || null,
        }),
      })

      if (!res.ok) {
        const text = await res.text()
        console.error("[admin-notify/beta-signup] API failed", {
          userId,
          status: res.status,
          body: text,
        })
      }
    } catch (err) {
      console.error("[admin-notify/beta-signup] request failed", { err })
    }
  })()
}
